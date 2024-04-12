import gleam/dynamic.{type Dynamic}
import gleam/result

pub fn map_err_dyn(res: Result(a, b)) -> Result(a, Dynamic) {
  result.map_error(res, dynamic.from)
}
