import gleam/bool.{guard}
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/task.{async, try_await}
import gleam/order.{Lt}
import gleam/result
import birl.{type Time}
import birl/duration.{hours}
import cal/utils.{map_err_dyn}
import cal/pjatk

pub type StateResult {
  StateResult(
    set_creds: fn(String, String) -> Nil,
    fetch_ics: fn() -> Result(String, Nil),
  )
}

type State {
  State(creds: Option(#(String, String)), cached_ics: String, last_fetch: Time)
}

type Message {
  SetCreds(#(String, String))
  FetchIcs(reply_with: Subject(Result(String, Nil)))
}

pub fn new_state() -> StateResult {
  let assert Ok(actor) =
    actor.start(
      State(creds: None, cached_ics: "", last_fetch: birl.from_unix(0)),
      handle_message,
    )

  let set_creds = fn(username, password) {
    process.send(actor, SetCreds(#(username, password)))
  }
  let fetch_ics = fn() {
    process.try_call(actor, FetchIcs, 15_000)
    |> result.map_error(fn(err) {
      io.debug(err)
      Nil
    })
    |> result.flatten
  }
  StateResult(set_creds, fetch_ics)
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    SetCreds(creds) -> {
      let new_state = State(..state, creds: Some(creds))
      actor.continue(new_state)
    }
    FetchIcs(client) -> {
      let State(creds, _ics, last_fetch) = state
      let new_state = {
        use creds <- result.try(option.to_result(
          creds,
          dynamic.from("no creds given"),
        ))
        use <- guard(
          when: duration.compare(
              birl.difference(birl.now(), last_fetch),
              hours(1),
            )
            == Lt,
          return: Ok(state),
        )
        let task = async(fn() { pjatk.fetch_ics(creds.0, creds.1) })
        use ics <- result.try(
          try_await(task, 10_000)
          |> map_err_dyn
          |> result.flatten,
        )
        Ok(State(Some(creds), ics, birl.now()))
      }
      process.send(
        client,
        new_state
          |> result.map(fn(state) { state.cached_ics })
          |> result.nil_error,
      )
      actor.continue(
        new_state
        |> result.lazy_unwrap(fn() {
          io.debug(new_state)
          state
        }),
      )
    }
  }
}
