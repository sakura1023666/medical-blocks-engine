block_render_figures <- function(ctx, ...) {
  get("render_queued_figures", mode = "function")(ctx)
}

register_block("render_figures", block_render_figures,
               "Render queued figure tasks in a dedicated figure block")
