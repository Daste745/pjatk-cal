import gleam/option.{Some, None}
import gleam/string
import gleam/http
import gleam/bytes_builder
import gleam/erlang/process
import gleam/erlang/os
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/result
import mist
import cal/state.{StateResult}

pub fn main() {
  let StateResult(set_creds, fetch_ics) = state.new_state()

  let port =
    os.get_env("PORT")
    |> result.try(int.parse)
    |> result.lazy_unwrap(fn() {
      io.println_error("No valid PORT given, falling back to 8080")
      8080
    })

  let username =
    os.get_env("PJATK_USERNAME")
    |> result.lazy_unwrap(fn() {
      panic as "No PJATK_USERNAME set, exiting!"
    })
  let password =
    os.get_env("PJATK_PASSWORD")
    |> result.lazy_unwrap(fn() {
      panic as "No PJATK_PASSWORD set, exiting!"
    })
  set_creds(username, password)

  let assert Ok(_) =
    mist.new(fn(req) {
      let res = case request.path_segments(req) {
        ["calendar.ics"] ->
          case fetch_ics() {
            Ok(ics) ->
              response.new(200)
              |> response.set_body(mist.Bytes(bytes_builder.from_string(ics)))
            Error(_) -> {
              response.new(500)
              |> response.set_body(mist.Bytes(bytes_builder.new()))
            }
          }
        _ ->
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_builder.new()))
      }

      // HTTP GET /some.thing?query=param 200
      io.println(
        "HTTP "
        |> string.append(req.method |> http.method_to_string |> string.uppercase)
        |> string.append(" ")
        |> string.append(req.path)
        |> string.append(
          case req.query {
            Some(query) -> "?" |> string.append(query)
            None -> ""
          }
        )
        |> string.append(" ")
        |> string.append(res.status |> int.to_string)
      )

      res
    })
    |> mist.port(port)
    |> mist.start_http

  process.sleep_forever()
}
