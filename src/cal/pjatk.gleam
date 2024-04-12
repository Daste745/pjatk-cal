import gleam/bool.{guard}
import gleam/dynamic.{type Dynamic}
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/iterator.{to_list, unfold}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string
import gleam/string_builder
import falcon/hackney
import cal/utils.{map_err_dyn}

pub fn fetch_ics(username: String, password: String) -> Result(String, Dynamic) {
  use resp <- result.try(send_asp_post(
    "https://planzajec.pjwstk.edu.pl/Logowanie.aspx",
    [
      #("ctl00$ContentPlaceHolder1$Login1$UserName", username),
      #("ctl00$ContentPlaceHolder1$Login1$Password", password),
      #("ctl00$ContentPlaceHolder1$Login1$LoginButton", "Zaloguj"),
    ],
    None,
  ))

  use <- guard(
    when: resp.status != 302,
    return: Error(#("expected a redirect", resp))
      |> map_err_dyn,
  )

  use cookie <- result.try(
    resp
    |> response.get_header("set-cookie")
    |> result.try(fn(head) { string.split_once(head, ";") })
    |> map_err_dyn
    |> result.map(pair.first),
  )

  use resp <- result.try(
    request.to("https://planzajec.pjwstk.edu.pl/TwojPlan.aspx")
    |> result.map(fn(req) { request.set_header(req, "cookie", cookie) })
    |> map_err_dyn
    |> result.try(send_with_err),
  )

  use cookie <- result.try(
    {
      use new_cookie <- result.map(
        resp
        |> response.get_header("set-cookie")
        |> result.try(fn(head) { string.split_once(head, ";") })
        |> result.map(pair.first),
      )
      cookie <> "; " <> new_cookie
    }
    |> map_err_dyn,
  )

  let resp =
    send_asp_post(
      "https://planzajec.pjwstk.edu.pl/TwojPlan.aspx",
      [
        #(
          "ctl00$ContentPlaceHolder1$DedykowanyPlanStudenta$CalendarICalExportButton",
          "Eksportuj do iCalendar",
        ),
      ],
      Some(cookie),
    )

  use <- guard(
    when: result.is_error(resp),
    return: Error(#("expected a success", resp))
      |> map_err_dyn,
  )

  use resp <- result.try(
    request.to("https://planzajec.pjwstk.edu.pl/TwojICal.aspx")
    |> result.map(fn(req) { request.set_header(req, "cookie", cookie) })
    |> map_err_dyn
    |> result.try(send_with_err),
  )

  Ok(resp.body)
}

fn send_with_err(req: Request(String)) -> Result(Response(String), Dynamic) {
  hackney.send(
    request.set_header(
      req,
      "user-agent",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:124.0) Gecko/20100101 Firefox/124.0",
    ),
    [hackney.FollowRedirect(False)],
  )
  |> result.map_error(fn(err) {
    let assert hackney.Other(e) = err
    e
  })
  |> result.try(fn(resp) {
    case resp.status {
      code if code >= 200 && code < 400 -> Ok(resp)
      code -> Error(dynamic.from(#(code, resp.body)))
    }
  })
}

@external(erlang, "uri_string", "quote")
fn percent_encode(s: String) -> String

fn req_set_form_body(
  req: Request(String),
  body: List(#(String, String)),
) -> Request(String) {
  let body =
    body
    |> list.map(fn(v) {
      string_builder.from_strings([
        percent_encode(v.0),
        "=",
        percent_encode(v.1),
      ])
    })
    |> list.intersperse(string_builder.from_string("&"))
    |> string_builder.concat
    |> string_builder.to_string
  req
  |> request.set_method(http.Post)
  |> request.set_header("Content-Type", "application/x-www-form-urlencoded")
  |> request.set_body(body)
}

fn send_asp_post(
  url: String,
  body: List(#(String, String)),
  cookie: Option(String),
) -> Result(Response(String), Dynamic) {
  let assert Ok(req) = request.to(url)
  let req =
    option.map(cookie, fn(cookie) { request.set_header(req, "Cookie", cookie) })
    |> option.unwrap(req)
  use resp <- result.try(send_with_err(req))
  let body = list.append(body, body_to_params(resp.body))

  let assert Ok(req) = request.to(url)
  let req =
    option.map(cookie, fn(cookie) { request.set_header(req, "Cookie", cookie) })
    |> option.unwrap(req)
    |> req_set_form_body(body)

  send_with_err(req)
}

fn value_from_elem(elem: String) -> Result(String, Nil) {
  use #(_, val) <- result.map(
    elem
    |> string.split_once("="),
  )

  val
  |> string.drop_left(1)
  |> string.drop_right(1)
}

fn get_elem(elems: List(String), name: String) -> Result(String, Nil) {
  result.try(
    list.find(elems, fn(e) { string.starts_with(e, name) }),
    value_from_elem,
  )
}

fn body_to_params(body: String) -> List(#(String, String)) {
  unfold(body, fn(body) {
    {
      use #(_, rest) <- result.try(string.split_once(
        body,
        "<input type=\"hidden\" ",
      ))
      use #(tag, rest) <- result.try(string.split_once(rest, " />"))
      let elems = string.split(tag, on: " ")
      use name <- result.try(get_elem(elems, "name"))
      use value <- result.try(get_elem(elems, "value"))

      Ok(iterator.Next(element: #(name, value), accumulator: rest))
    }
    |> result.unwrap(iterator.Done)
  })
  |> to_list
}
