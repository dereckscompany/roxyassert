#!/usr/bin/env Rscript
# ============================================================================
# LOGO.R - Generate the hpfi hex sticker
# ============================================================================
# Multi-layer compositing: ggplot2 renders layers, magick applies real
# gaussian blur, motion blur, and glow via blend modes.
#
# Retro-futuristic speedometer. Cassette futurism. Warm incandescent glow.
# 310-degree gauge, gap at bottom, 0 left -> 3+ right (clockwise).
#
# Usage:  Rscript scripts/LOGO.R
# Deps:   ggplot2, magick
# ============================================================================

library(ggplot2)
library(magick)

# ============================================================================
# Palette
# ============================================================================

col_hex_fill <- "#080B11"
col_labels <- "#F0E6D2"
col_ticks_minor <- "#2A3040"
col_needle <- "#FF3B4A"
col_hub_outer <- "#F0E6D2"
col_hub_inner <- "#FF3B4A"
col_zone_1 <- "#2a4c76ff" # dark steel-blue (brighter, bluer)
col_zone_2 <- "#18753E" # emerald (boosted)
col_zone_3 <- "#e8cf10ff" # gold (boosted)
col_zone_4 <- "#ff8324ff" # orange
col_zone_5 <- "#e81d2eff" # hot red (boosted)
col_title <- "#FFFFFF"
col_sharpe <- "#B0A08A"

# ============================================================================
# Gauge geometry
# ============================================================================

gauge_r <- 0.34
gauge_cx <- 0.0
gauge_cy <- 0.0 # centred on hex geometric centre

# CW reading: 0 at bottom-left (245 deg), 3+ at bottom-right (-65 deg)
arc_start_deg <- 245
arc_end_deg <- -65

tick_values <- c(0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0)
tick_labels_v <- c("0", "0.5", "1", "1.5", "2", "2.5", "3+")
needle_value <- 2.7

zone_breaks <- c(0, 0.6, 1.2, 1.8, 2.4, 3.0)
zone_colours <- c(col_zone_1, col_zone_2, col_zone_3, col_zone_4, col_zone_5)

# ============================================================================
# Helpers
# ============================================================================

deg2rad <- function(d) d * pi / 180

val2angle <- function(v, vmin = 0, vmax = 3.0) {
  frac <- pmin(pmax((v - vmin) / (vmax - vmin), 0), 1)
  arc_start_deg + frac * (arc_end_deg - arc_start_deg)
}

hex_vertices <- function(cx = 0, cy = 0, r = 1) {
  angles <- seq(pi / 2, pi / 2 + 2 * pi, length.out = 7)[1:6]
  data.frame(x = cx + r * cos(angles), y = cy + r * sin(angles))
}

arc_polygon <- function(cx, cy, r_inner, r_outer, a_start, a_end, n = 300) {
  angles <- seq(deg2rad(a_start), deg2rad(a_end), length.out = n)
  data.frame(
    x = c(cx + r_outer * cos(angles), rev(cx + r_inner * cos(angles))),
    y = c(cy + r_outer * sin(angles), rev(cy + r_inner * sin(angles)))
  )
}

filled_circle <- function(cx, cy, r, n = 150) {
  angles <- seq(0, 2 * pi, length.out = n)
  data.frame(x = cx + r * cos(angles), y = cy + r * sin(angles))
}

# Standard theme for all layers
logo_theme <- function() {
  theme_void() +
    theme(
      plot.background = element_rect(fill = "transparent", colour = NA),
      panel.background = element_rect(fill = "transparent", colour = NA),
      plot.margin = margin(0, 0, 0, 0)
    )
}

# Standard coord for all layers
logo_coord <- function() {
  coord_equal(xlim = c(-0.67, 0.67), ylim = c(-0.67, 0.67))
}

# Render a ggplot to a magick image
render_layer <- function(p, width = 3000, height = 3480) {
  tmp <- tempfile(fileext = ".png")
  ggsave(tmp, plot = p, width = width / 600, height = height / 600, dpi = 600, bg = "transparent")
  img <- image_read(tmp)
  unlink(tmp)
  img
}

# ============================================================================
# Build shared data
# ============================================================================

build_data <- function() {
  hex_outer <- hex_vertices(0, 0, 0.57)

  arc_zones <- lapply(seq_along(zone_colours), function(i) {
    df <- arc_polygon(
      gauge_cx,
      gauge_cy,
      r_inner = gauge_r * 0.73,
      r_outer = gauge_r * 1.00,
      a_start = val2angle(zone_breaks[i]),
      a_end = val2angle(zone_breaks[i + 1])
    )
    df$zone <- paste0("z", i)
    df
  })
  arc_df <- do.call(rbind, arc_zones)

  # Rims
  outer_rim <- arc_polygon(gauge_cx, gauge_cy, gauge_r * 1.00, gauge_r * 1.03, arc_start_deg, arc_end_deg)
  inner_rim <- arc_polygon(gauge_cx, gauge_cy, gauge_r * 0.70, gauge_r * 0.73, arc_start_deg, arc_end_deg)

  # Major ticks
  major_ticks <- do.call(
    rbind,
    lapply(seq_along(tick_values), function(i) {
      a <- deg2rad(val2angle(tick_values[i]))
      data.frame(
        x0 = gauge_cx + gauge_r * 0.50 * cos(a),
        y0 = gauge_cy + gauge_r * 0.50 * sin(a),
        x1 = gauge_cx + gauge_r * 1.03 * cos(a),
        y1 = gauge_cy + gauge_r * 1.03 * sin(a),
        lx = gauge_cx + gauge_r * 1.28 * cos(a),
        ly = gauge_cy + gauge_r * 1.28 * sin(a),
        lab = tick_labels_v[i],
        stringsAsFactors = FALSE
      )
    })
  )

  # Minor ticks
  minor_vals <- setdiff(seq(0, 3.0, by = 0.25), tick_values)
  minor_ticks <- do.call(
    rbind,
    lapply(minor_vals, function(v) {
      a <- deg2rad(val2angle(v))
      data.frame(
        x0 = gauge_cx + gauge_r * 0.78 * cos(a),
        y0 = gauge_cy + gauge_r * 0.78 * sin(a),
        x1 = gauge_cx + gauge_r * 1.00 * cos(a),
        y1 = gauge_cy + gauge_r * 1.00 * sin(a),
        stringsAsFactors = FALSE
      )
    })
  )

  # Needle geometry — flat/square tip, tapered body
  needle_a <- deg2rad(val2angle(needle_value))
  needle_len <- gauge_r * 0.95
  tail_len <- gauge_r * 0.15
  perp_a <- needle_a + pi / 2
  half_w_tip <- 0.005 # width at tip (narrow flat end)
  half_w_base <- 0.016 # width at base

  # 4-point polygon: rectangular/trapezoidal needle
  needle_poly <- data.frame(
    x = c(
      gauge_cx + needle_len * cos(needle_a) + half_w_tip * cos(perp_a),
      gauge_cx + needle_len * cos(needle_a) - half_w_tip * cos(perp_a),
      gauge_cx - tail_len * cos(needle_a) - half_w_base * cos(perp_a),
      gauge_cx - tail_len * cos(needle_a) + half_w_base * cos(perp_a)
    ),
    y = c(
      gauge_cy + needle_len * sin(needle_a) + half_w_tip * sin(perp_a),
      gauge_cy + needle_len * sin(needle_a) - half_w_tip * sin(perp_a),
      gauge_cy - tail_len * sin(needle_a) - half_w_base * sin(perp_a),
      gauge_cy - tail_len * sin(needle_a) + half_w_base * sin(perp_a)
    )
  )

  # Tip accent line (bright white across the flat tip)
  needle_tip_line <- data.frame(
    x0 = gauge_cx + needle_len * cos(needle_a) + half_w_tip * cos(perp_a),
    y0 = gauge_cy + needle_len * sin(needle_a) + half_w_tip * sin(perp_a),
    x1 = gauge_cx + needle_len * cos(needle_a) - half_w_tip * cos(perp_a),
    y1 = gauge_cy + needle_len * sin(needle_a) - half_w_tip * sin(perp_a)
  )

  # Base accent line (across the base end)
  needle_base_line <- data.frame(
    x0 = gauge_cx - tail_len * cos(needle_a) + half_w_base * cos(perp_a),
    y0 = gauge_cy - tail_len * sin(needle_a) + half_w_base * sin(perp_a),
    x1 = gauge_cx - tail_len * cos(needle_a) - half_w_base * cos(perp_a),
    y1 = gauge_cy - tail_len * sin(needle_a) - half_w_base * sin(perp_a)
  )

  # Centre line detail (thin dark line running along the needle's length)
  needle_centre_line <- data.frame(
    x0 = gauge_cx + needle_len * 0.85 * cos(needle_a),
    y0 = gauge_cy + needle_len * 0.85 * sin(needle_a),
    x1 = gauge_cx - tail_len * 0.5 * cos(needle_a),
    y1 = gauge_cy - tail_len * 0.5 * sin(needle_a)
  )

  needle_tip <- data.frame(
    x = gauge_cx + needle_len * cos(needle_a),
    y = gauge_cy + needle_len * sin(needle_a)
  )

  # Needle angle in image-space degrees (for motion blur)
  # ggplot angle -> image angle: image y is flipped
  needle_img_angle <- -(val2angle(needle_value))

  list(
    hex_outer = hex_outer,
    arc_df = arc_df,
    outer_rim = outer_rim,
    inner_rim = inner_rim,
    major_ticks = major_ticks,
    minor_ticks = minor_ticks,
    needle_poly = needle_poly,
    needle_tip_line = needle_tip_line,
    needle_base_line = needle_base_line,
    needle_centre_line = needle_centre_line,
    needle_tip = needle_tip,
    needle_img_angle = needle_img_angle
  )
}

# ============================================================================
# Layer 1: Base (hex, zones, ticks, labels, text)
# ============================================================================

build_base_layer <- function(d) {
  ggplot() +
    # Hex fill
    geom_polygon(data = d$hex_outer, aes(x, y), fill = col_hex_fill, colour = NA) +
    # Outer rim
    geom_polygon(data = d$outer_rim, aes(x, y), fill = "#1A1F2B", colour = NA) +
    # Arc zones
    geom_polygon(data = d$arc_df, aes(x, y, group = zone, fill = zone), colour = NA) +
    scale_fill_manual(
      values = setNames(zone_colours, paste0("z", seq_along(zone_colours))),
      guide = "none"
    ) +
    # Inner rim
    geom_polygon(data = d$inner_rim, aes(x, y), fill = "#1A1F2B", colour = NA) +
    # Minor ticks
    geom_segment(
      data = d$minor_ticks,
      aes(x = x0, y = y0, xend = x1, yend = y1),
      colour = col_ticks_minor,
      linewidth = 0.5
    ) +
    # Major ticks
    geom_segment(
      data = d$major_ticks,
      aes(x = x0, y = y0, xend = x1, yend = y1),
      colour = col_labels,
      linewidth = 1.8
    ) +
    # Tick labels
    geom_text(
      data = d$major_ticks,
      aes(x = lx, y = ly, label = lab),
      colour = col_labels,
      size = 4.5,
      fontface = "bold"
    ) +
    # SHARPE label
    annotate(
      "text",
      x = gauge_cx,
      y = gauge_cy - 0.09,
      label = "SHARPE",
      colour = col_sharpe,
      size = 3.0,
      fontface = "bold"
    ) +
    # Hub (base ring)
    annotate("point", x = gauge_cx, y = gauge_cy, size = 5.0, colour = col_hub_outer, shape = 16) +
    annotate("point", x = gauge_cx, y = gauge_cy, size = 3.0, colour = col_hub_inner, shape = 16) +
    # "hpfi" -- centred in the bottom gap
    annotate(
      "text",
      x = -0.01,
      y = -0.40,
      label = "hpfi",
      colour = col_title,
      size = 12,
      fontface = "bold.italic",
      family = "sans"
    ) +
    logo_coord() +
    logo_theme()
}

# ============================================================================
# Layer 2: Needle + sweep wedge
# ============================================================================

# The sharp main needle (rendered separately for crisp overlay)
build_needle_layer <- function(d) {
  ggplot() +
    # Main needle body
    geom_polygon(data = d$needle_poly, aes(x, y), fill = col_needle, colour = NA) +
    # Tip accent (bright white line across the flat tip)
    geom_segment(
      data = d$needle_tip_line,
      aes(x = x0, y = y0, xend = x1, yend = y1),
      colour = "#FFFFFFCC",
      linewidth = 1.2
    ) +
    # Base accent (dark line across the base)
    geom_segment(
      data = d$needle_base_line,
      aes(x = x0, y = y0, xend = x1, yend = y1),
      colour = "#3e101fff",
      linewidth = 1.5
    ) +
    # Centre groove (thin dark line along the needle body)
    geom_segment(
      data = d$needle_centre_line,
      aes(x = x0, y = y0, xend = x1, yend = y1),
      colour = "#54070b80",
      linewidth = 0.4
    ) +
    logo_coord() +
    logo_theme()
}

# Sweep wedge: graduated opacity — nearly invisible at 0, intensifying toward
# the needle position, as if the needle swept across and faded in.
# Split into multiple arc slices so opacity can ramp up progressively.
build_sweep_layer <- function(d) {
  n_slices <- 24

  # Opacity ramps: power curve keeps low end faint, top end punchy.
  alphas <- (seq(0, 1.1, length.out = n_slices))^2.2 * 0.3

  # Extend sweep slightly past needle so the glow wraps around it
  sweep_overshoot <- needle_value + 0.19
  slice_vals <- seq(0, sweep_overshoot, length.out = n_slices + 1)

  p <- ggplot()
  for (i in seq_len(n_slices)) {
    arc_slice <- arc_polygon(
      gauge_cx,
      gauge_cy,
      r_inner = gauge_r * 0.10,
      r_outer = gauge_r * 0.92,
      a_start = val2angle(slice_vals[i]),
      a_end = val2angle(slice_vals[i + 1])
    )
    p <- p + geom_polygon(data = arc_slice, aes(x, y), fill = col_needle, alpha = alphas[i], colour = NA)
  }

  # Bright outer-edge trail for the last 40% of sweep (tip trail)
  tip_arc <- arc_polygon(
    gauge_cx,
    gauge_cy,
    r_inner = gauge_r * 0.75,
    r_outer = gauge_r * 0.96,
    a_start = val2angle(needle_value * 0.5),
    a_end = val2angle(sweep_overshoot)
  )
  p <- p + geom_polygon(data = tip_arc, aes(x, y), fill = col_needle, alpha = 0.18, colour = NA)

  p + logo_coord() + logo_theme()
}

# Ghost needles: a few faint needle silhouettes clustered near the main needle
# to suggest rapid oscillation/arrival at the final position.
build_ghost_layer <- function(d) {
  # Positions clustered near needle_value (e.g., 2.1, 2.35, 2.55)
  ghost_vals <- c(needle_value - 0.6, needle_value - 0.35, needle_value - 0.15, needle_value + 0.15)
  ghost_alphas <- c(0.2, 0.35, 0.65, 0.65)

  p <- ggplot()
  for (i in seq_along(ghost_vals)) {
    ga <- deg2rad(val2angle(ghost_vals[i]))
    nlen <- gauge_r * 0.95
    tlen <- gauge_r * 0.15
    perp <- ga + pi / 2
    hw_tip <- 0.008
    hw_base <- 0.016

    gpoly <- data.frame(
      x = c(
        gauge_cx + nlen * cos(ga) + hw_tip * cos(perp),
        gauge_cx + nlen * cos(ga) - hw_tip * cos(perp),
        gauge_cx - tlen * cos(ga) - hw_base * cos(perp),
        gauge_cx - tlen * cos(ga) + hw_base * cos(perp)
      ),
      y = c(
        gauge_cy + nlen * sin(ga) + hw_tip * sin(perp),
        gauge_cy + nlen * sin(ga) - hw_tip * sin(perp),
        gauge_cy - tlen * sin(ga) - hw_base * sin(perp),
        gauge_cy - tlen * sin(ga) + hw_base * sin(perp)
      )
    )
    p <- p + geom_polygon(data = gpoly, aes(x, y), fill = col_needle, alpha = ghost_alphas[i], colour = NA)
  }
  p + logo_coord() + logo_theme()
}

# ============================================================================
# Layer 3: Glow sources (bright spots to blur into glow)
# ============================================================================

build_glow_layer <- function(d) {
  # Needle tip hot spot
  tip <- d$needle_tip

  # Arc highlight: thin bright line along the red zone outer edge
  red_arc <- arc_polygon(gauge_cx, gauge_cy, gauge_r * 0.98, gauge_r * 1.02, val2angle(2.4), val2angle(3.0))

  # Hub glow source
  hub_circle <- filled_circle(gauge_cx, gauge_cy, 0.025)

  ggplot() +
    # Needle tip glow source (BRIGHT red dot -- big)
    annotate("point", x = tip$x, y = tip$y, size = 10, colour = "#FF3B4AFF", shape = 16) +
    # Hub glow source (warm)
    geom_polygon(data = hub_circle, aes(x, y), fill = "#FF3B4ACC", colour = NA) +
    # Red zone outer edge glow (brighter)
    geom_polygon(data = red_arc, aes(x, y), fill = "#FF3B4A70", colour = NA) +
    # Gold zone glow (subtle warmth from the gold arc)
    geom_polygon(
      data = arc_polygon(gauge_cx, gauge_cy, gauge_r * 0.98, gauge_r * 1.02, val2angle(1.2), val2angle(1.8)),
      aes(x, y),
      fill = "#E8B01040",
      colour = NA
    ) +
    # Orange zone glow
    geom_polygon(
      data = arc_polygon(gauge_cx, gauge_cy, gauge_r * 0.98, gauge_r * 1.02, val2angle(1.8), val2angle(2.4)),
      aes(x, y),
      fill = "#F0802035",
      colour = NA
    ) +
    # Green zone subtle glow
    geom_polygon(
      data = arc_polygon(gauge_cx, gauge_cy, gauge_r * 0.98, gauge_r * 1.02, val2angle(0.6), val2angle(1.2)),
      aes(x, y),
      fill = "#18753E20",
      colour = NA
    ) +
    # Ambient centre warmth
    annotate("point", x = gauge_cx, y = gauge_cy, size = 30, colour = "#88AACC15", shape = 16) +
    logo_coord() +
    logo_theme()
}

# ============================================================================
# Composite with magick
# ============================================================================

generate_logo <- function(
  output_path = file.path("man", "figures", "logo.png"),
  px_width = 3000,
  px_height = 3480
) {
  d <- build_data()

  message("Rendering base layer...")
  base_img <- render_layer(build_base_layer(d), px_width, px_height)

  message("Rendering needle layer (sharp)...")
  needle_img <- render_layer(build_needle_layer(d), px_width, px_height)

  message("Rendering sweep wedge layer...")
  sweep_img <- render_layer(build_sweep_layer(d), px_width, px_height)

  message("Rendering ghost needles layer...")
  ghost_img <- render_layer(build_ghost_layer(d), px_width, px_height)

  message("Rendering glow layer...")
  glow_img <- render_layer(build_glow_layer(d), px_width, px_height)

  # -- Blur the sweep wedge heavily so it becomes a smooth continuous smear
  message("Blurring sweep wedge...")
  sweep_soft <- image_blur(sweep_img, radius = 0, sigma = 15)
  sweep_wide <- image_blur(sweep_img, radius = 0, sigma = 35)

  # -- Blur ghost needles (soft motion blur so they look like afterimages)
  message("Blurring ghost needles...")
  ghost_blur <- image_blur(ghost_img, radius = 0, sigma = 8)

  # -- Motion blur on the sharp needle (tangent to arc)
  message("Applying motion blur to sharp needle...")
  needle_blur <- image_motion_blur(needle_img, radius = 0, sigma = 25, angle = 124)

  # -- Gaussian blur glow sources
  message("Applying gaussian blur for glow...")
  glow_wide <- image_blur(glow_img, radius = 0, sigma = 40)
  glow_mid <- image_blur(glow_img, radius = 0, sigma = 20)
  glow_tight <- image_blur(glow_img, radius = 0, sigma = 8)

  # -- Composite everything
  message("Compositing layers...")
  final <- base_img |>
    image_composite(glow_wide, operator = "screen") |> # big soft halo
    image_composite(glow_mid, operator = "screen") |> # medium glow
    image_composite(glow_tight, operator = "screen") |> # tight hot core
    image_composite(sweep_wide, operator = "screen") |> # wide diffuse sweep
    image_composite(sweep_soft, operator = "screen") |> # tighter sweep glow
    image_composite(ghost_blur, operator = "screen") |> # faint ghost needles
    image_composite(needle_blur, operator = "over") |> # motion-blurred needle
    image_composite(needle_img, operator = "over") # sharp needle on top

  # Trim transparent border
  final <- image_trim(final)

  # Ensure output dir exists
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  image_write(final, output_path, format = "png")
  message("Logo saved to: ", output_path)

  # Copy to pkgdown dirs
  for (dest in c("docs/logo.png", "docs/reference/figures/logo.png")) {
    if (dir.exists(dirname(dest))) {
      file.copy(output_path, dest, overwrite = TRUE)
      message("Copied to:    ", dest)
    }
  }

  invisible(final)
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
