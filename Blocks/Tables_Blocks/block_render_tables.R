block_render_tables <- function(ctx, ...) {
  get("render_queued_tables", mode = "function")(ctx)
}

register_block("render_tables", block_render_tables,
               "Render queued LaTeX table tasks in a dedicated table block")
