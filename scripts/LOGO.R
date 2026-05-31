#!/usr/bin/env Rscript
# ============================================================================
# LOGO.R - Generate the roxyassert hex sticker
# ============================================================================
# Multi-layer compositing: ggplot2 renders layers, magick applies a real
# gaussian-blur glow via screen blending.
#
# Concept: roxyassert turns typed roxygen documentation into runtime checks.
# So the motif is "docs -> generated check": a glowing green checkmark whose
# long arm grows out of a small stack of roxygen doc-lines (the `#'` markers).
# The documentation on the left literally flows into the asserted-true mark on
# the right. A thin inner hex "gate" ring frames it -- the same guarded gate as
# the sibling `assert` sticker. Dark slate field, confident green check, soft
# glow. The "roxyassert" wordmark sits below.
#
# Deliberately a sibling of assert's sticker (same palette, hex, glow, gate
# rings, wordmark style) -- not a copy: the check is born from doc-lines here,
# rather than standing alone.
#
# Usage:  Rscript scripts/LOGO.R
# Deps:   ggplot2, magick
# ============================================================================

library(ggplot2)
library(magick)

# ============================================================================
# Palette  (identical family to assert)
# ============================================================================

col_hex_fill <- "#0E1320" # deep slate field
col_hex_edge <- "#2BD46A" # green hex border
col_central <- "#8FB0A0" # central solid hexagon (lightest greyish-green)
col_check <- "#2BD46A" # the checkmark — valid green
col_check_core <- "#9CF7C2" # bright inner highlight of the check
col_doc <- "#2BD46A" # roxygen doc-lines — same green as the check
col_doc_core <- "#9CF7C2" # bright inner highlight of the doc-lines
col_doc_hash <- "#6FE2A0" # the `#'` markers, a touch softer
col_glow <- "#2BD46A" # glow source colour
col_wordmark <- "#F0F4F8" # near-white wordmark

# ============================================================================
# Geometry helpers
# ============================================================================

# Pointy-top hexagon vertices (vertex at the top), radius r, centred at (cx, cy).
hex_vertices <- function(cx = 0, cy = 0, r = 1) {
  angles <- seq(pi / 2, pi / 2 + 2 * pi, length.out = 7)[1:6]
  return(data.frame(x = cx + r * cos(angles), y = cy + r * sin(angles)))
}

# The three points of the checkmark stroke (short arm then long arm).
# Nudged right so the doc-lines have clear room on the left, and the elbow
# sits just past where the top doc-line ends -- so the long arm reads as the
# documentation "flowing out" into the generated check.
check_path <- function() {
  return(data.frame(
    x = c(-0.020, 0.150, 0.355),
    y = c(0.020, -0.165, 0.300)
  ))
}

# Roxygen doc-lines: a small stack of horizontal bars on the left, each
# prefixed by a `#'` marker. They represent the typed `@param` / `@return`
# documentation that roxyassert reads. The top line points toward the
# checkmark's elbow so the check appears to grow out of the documentation.
doc_lines <- function() {
  # y positions of each doc-line (top line aligns with the check elbow).
  ys <- c(0.020, -0.115, -0.250)
  # The horizontal bar of each line: start x and end x. Kept short so they
  # sit clearly to the LEFT of the check's short arm, never colliding.
  starts <- c(-0.230, -0.230, -0.230)
  ends <- c(-0.075, -0.135, -0.175) # ragged right edge, like real doc text
  return(data.frame(y = ys, x0 = starts, x1 = ends))
}

# Position of the `#'` hash-prime markers (one per doc-line), to the left of
# each bar.
doc_hashes <- function() {
  dl <- doc_lines()
  return(data.frame(x = rep(-0.315, nrow(dl)), y = dl$y))
}

logo_theme <- function() {
  return(
    theme_void() +
      theme(
        plot.background = element_rect(fill = "transparent", colour = NA),
        panel.background = element_rect(fill = "transparent", colour = NA),
        plot.margin = margin(0, 0, 0, 0)
      )
  )
}

logo_coord <- function() {
  return(coord_equal(xlim = c(-0.67, 0.67), ylim = c(-0.67, 0.67)))
}

# Render a ggplot to a magick image on a transparent background.
render_layer <- function(p, width = 3000, height = 3480) {
  tmp <- tempfile(fileext = ".png")
  ggsave(tmp, plot = p, width = width / 600, height = height / 600, dpi = 600, bg = "transparent")
  img <- image_read(tmp)
  unlink(tmp)
  return(img)
}

# ============================================================================
# Layers
# ============================================================================

# Base: hex field, border, inner gate ring, the doc-lines, the checkmark
# growing out of them, and the wordmark.
build_base_layer <- function() {
  hex_outer <- hex_vertices(0, 0, 0.62)
  check <- check_path()
  dl <- doc_lines()
  dh <- doc_hashes()

  # Concentric hexagon outlines stepping inward from the border, tinted in a
  # greyish-green gradient (darker outside, lighter toward the centre). Drawn as
  # closed polygons with mitred corners so the rings meet cleanly at every
  # vertex (an open path leaves a notch at the top).
  ring_radii <- c(0.52, 0.43, 0.34, 0.25, 0.16)
  ring_palette <- grDevices::colorRampPalette(c("#2E3A34", "#7E9C8A"))(length(ring_radii))
  rings <- lapply(seq_along(ring_radii), function(i) {
    hv <- hex_vertices(0, 0, ring_radii[i])
    geom_polygon(
      data = hv,
      aes(x, y),
      fill = NA,
      colour = ring_palette[i],
      linewidth = 4,
      linejoin = "mitre"
    )
  })
  # The innermost hexagon is solid, continuing the gradient.
  hex_centre <- hex_vertices(0, 0, 0.08)

  ggplot() +
    # Hex field
    geom_polygon(data = hex_outer, aes(x, y), fill = col_hex_fill, colour = col_hex_edge, linewidth = 7) +
    # Concentric "gate" rings
    rings +
    # Central solid hexagon
    geom_polygon(data = hex_centre, aes(x, y), fill = col_central, colour = NA) +
    # Roxygen doc-lines — outer stroke
    geom_segment(
      data = dl,
      aes(x = x0, y = y, xend = x1, yend = y),
      colour = col_doc,
      linewidth = 11,
      lineend = "round"
    ) +
    # Roxygen doc-lines — bright inner highlight
    geom_segment(
      data = dl,
      aes(x = x0, y = y, xend = x1, yend = y),
      colour = col_doc_core,
      linewidth = 3.5,
      lineend = "round"
    ) +
    # `#'` markers (the roxygen prefix), one per doc-line
    geom_text(
      data = dh,
      aes(x, y, label = "#'"),
      colour = col_doc_hash,
      size = 10,
      fontface = "bold",
      family = "mono",
      hjust = 0.5,
      vjust = 0.55
    ) +
    # Checkmark — outer stroke (grows out of the top doc-line)
    geom_path(
      data = check,
      aes(x, y),
      colour = col_check,
      linewidth = 18,
      lineend = "round",
      linejoin = "round"
    ) +
    # Checkmark — bright inner highlight
    geom_path(
      data = check,
      aes(x, y),
      colour = col_check_core,
      linewidth = 6,
      lineend = "round",
      linejoin = "round"
    ) +
    # Wordmark
    annotate(
      "text",
      x = 0,
      y = -0.40,
      label = "roxyassert",
      colour = col_wordmark,
      size = 11,
      fontface = "bold",
      family = "sans"
    ) +
    logo_coord() +
    logo_theme()
}

# Glow source: the doc-lines and the checkmark, fat and bright, to be blurred.
# Glowing the doc-lines too ties the "docs -> check" flow together in light.
build_glow_layer <- function() {
  check <- check_path()
  dl <- doc_lines()
  ggplot() +
    geom_segment(
      data = dl,
      aes(x = x0, y = y, xend = x1, yend = y),
      colour = col_glow,
      linewidth = 14,
      lineend = "round"
    ) +
    geom_path(
      data = check,
      aes(x, y),
      colour = col_glow,
      linewidth = 21,
      lineend = "round",
      linejoin = "round"
    ) +
    logo_coord() +
    logo_theme()
}

# ============================================================================
# Composite
# ============================================================================

generate_logo <- function(
  output_path = file.path("man", "figures", "logo.png"),
  px_width = 3000,
  px_height = 3480
) {
  message("Rendering base layer...")
  base_img <- render_layer(build_base_layer(), px_width, px_height)

  message("Rendering glow layer...")
  glow_img <- render_layer(build_glow_layer(), px_width, px_height)

  message("Blurring glow...")
  glow_wide <- image_blur(glow_img, radius = 0, sigma = 45)
  glow_tight <- image_blur(glow_img, radius = 0, sigma = 15)

  message("Compositing...")
  final <- base_img |>
    image_composite(glow_wide, operator = "screen") |>
    image_composite(glow_tight, operator = "screen") |>
    image_composite(base_img, operator = "over")

  final <- image_trim(final)

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  image_write(final, output_path, format = "png")
  message("Logo saved to: ", output_path)

  for (dest in c("docs/logo.png", "docs/reference/figures/logo.png")) {
    if (dir.exists(dirname(dest))) {
      file.copy(output_path, dest, overwrite = TRUE)
      message("Copied to:    ", dest)
    }
  }

  return(invisible(final))
}

# ============================================================================
# Run
# ============================================================================

if (!interactive() || identical(Sys.getenv("LOGO_GENERATE"), "true")) {
  generate_logo()
} else {
  message("Source this file and call generate_logo() to create the sticker.")
  message("Or run: Rscript scripts/LOGO.R")
}
