package com.example.locationmocker.presentation

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Point
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.route.RouteMath
import com.example.locationmocker.domain.track.SegmentedTrack
import com.example.locationmocker.domain.track.TrackOrientation
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

object TrackMapSegmenter {
    fun segment(
        bitmap: Bitmap,
        tapPoint: Point,
        pixelToRoutePoint: (Point) -> RoutePoint?,
    ): SegmentedTrack? {
        if (bitmap.width <= 0 || bitmap.height <= 0) return null

        val radius = min(520, min(bitmap.width, bitmap.height) / 2)
        val left = (tapPoint.x - radius).coerceAtLeast(0)
        val top = (tapPoint.y - radius).coerceAtLeast(0)
        val right = (tapPoint.x + radius).coerceAtMost(bitmap.width - 1)
        val bottom = (tapPoint.y + radius).coerceAtMost(bitmap.height - 1)
        val tappedField = findBestComponent(
            bitmap = bitmap,
            left = left,
            top = top,
            right = right,
            bottom = bottom,
            tapPoint = tapPoint,
            pixelMatcher = ::isFieldPixel,
            minArea = 900,
            minSide = 55,
        )?.takeIf { it.contains(tapPoint) || it.distanceTo(tapPoint) <= FIELD_TAP_TOLERANCE_PIXELS }
        val targetPoint = tappedField?.let { Point(it.centerX, it.centerY) } ?: tapPoint
        val track = findBestComponent(
            bitmap = bitmap,
            left = left,
            top = top,
            right = right,
            bottom = bottom,
            tapPoint = targetPoint,
            requiredInnerPoint = tappedField?.let { Point(it.centerX, it.centerY) },
            pixelMatcher = ::isTrackPixel,
            minArea = 900,
            minSide = 90,
        ) ?: return null

        val field = tappedField?.takeIf { track.contains(Point(it.centerX, it.centerY)) } ?: findBestComponent(
            bitmap = bitmap,
            left = track.minX,
            top = track.minY,
            right = track.maxX,
            bottom = track.maxY,
            tapPoint = Point(track.centerX, track.centerY),
            pixelMatcher = ::isFieldPixel,
            minArea = 900,
            minSide = 55,
        )

        val centerPixel = field
            ?.takeIf { it.area > track.area * 0.08 }
            ?.let { Point(it.centerX, it.centerY) }
            ?: Point(track.centroidX, track.centroidY)
        val center = pixelToRoutePoint(centerPixel) ?: return null
        val rotationDegrees = componentRotationDegrees(
            component = track,
            centerPixel = centerPixel,
            center = center,
            pixelToRoutePoint = pixelToRoutePoint,
        )
        val useAxisAlignedSize = rotationDegrees?.let { axisAlignmentDeviationDegrees(it) <= 12.0 } != false
        val widthMeters = if (useAxisAlignedSize) componentWidthMeters(track, pixelToRoutePoint) else null
        val heightMeters = if (useAxisAlignedSize) componentHeightMeters(track, pixelToRoutePoint) else null
        val orientation = if (rotationDegrees?.let { abs(normalizeAxisDegrees(it) - 90.0) < 45.0 } == true) {
            TrackOrientation.Vertical
        } else if (rotationDegrees != null) {
            TrackOrientation.Horizontal
        } else if (track.height >= track.width) {
            TrackOrientation.Vertical
        } else {
            TrackOrientation.Horizontal
        }
        val confidence = (
            45 +
                (track.area / 1_800).coerceAtMost(35) +
                if (track.contains(tapPoint)) 12 else 0 +
                if (field != null) 8 else 0
            ).coerceIn(0, 100)

        return SegmentedTrack(
            center = center,
            orientation = orientation,
            confidence = confidence,
            rotationDegrees = rotationDegrees,
            outerWidthMeters = widthMeters,
            outerHeightMeters = heightMeters,
        )
    }

    private fun findBestComponent(
        bitmap: Bitmap,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        tapPoint: Point,
        requiredInnerPoint: Point? = null,
        pixelMatcher: (Int) -> Boolean,
        minArea: Int,
        minSide: Int,
    ): Component? {
        val width = right - left + 1
        val height = bottom - top + 1
        if (width <= 1 || height <= 1) return null

        val mask = BooleanArray(width * height)
        val visited = BooleanArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                mask[y * width + x] = pixelMatcher(bitmap.getPixel(left + x, top + y))
            }
        }
        dilate(mask, width, height)

        val queue = IntArray(width * height)
        var best: Component? = null
        for (index in mask.indices) {
            if (!mask[index] || visited[index]) continue

            var head = 0
            var tail = 0
            queue[tail++] = index
            visited[index] = true
            var area = 0
            var sumX = 0L
            var sumY = 0L
            var sumX2 = 0.0
            var sumY2 = 0.0
            var sumXY = 0.0
            var minX = Int.MAX_VALUE
            var minY = Int.MAX_VALUE
            var maxX = Int.MIN_VALUE
            var maxY = Int.MIN_VALUE

            while (head < tail) {
                val current = queue[head++]
                val x = current % width
                val y = current / width
                area++
                sumX += x.toLong()
                sumY += y.toLong()
                sumX2 += x.toDouble() * x.toDouble()
                sumY2 += y.toDouble() * y.toDouble()
                sumXY += x.toDouble() * y.toDouble()
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)

                fun push(nx: Int, ny: Int) {
                    if (nx !in 0 until width || ny !in 0 until height) return
                    val next = ny * width + nx
                    if (!mask[next] || visited[next]) return
                    visited[next] = true
                    queue[tail++] = next
                }

                for (ny in y - 1..y + 1) {
                    for (nx in x - 1..x + 1) {
                        if (nx != x || ny != y) push(nx, ny)
                    }
                }
            }

            val component = Component(
                area = area,
                minX = minX + left,
                minY = minY + top,
                maxX = maxX + left,
                maxY = maxY + top,
                centroidX = (sumX / area + left).toInt(),
                centroidY = (sumY / area + top).toInt(),
                covarianceXX = sumX2 / area - (sumX.toDouble() / area).let { it * it },
                covarianceYY = sumY2 / area - (sumY.toDouble() / area).let { it * it },
                covarianceXY = sumXY / area - (sumX.toDouble() / area) * (sumY.toDouble() / area),
            )
            if (component.area < minArea || component.width < minSide || component.height < minSide) continue
            if (requiredInnerPoint != null && !component.contains(requiredInnerPoint)) continue

            val aspect = component.aspectRatio
            if (aspect !in 1.15..4.2) continue

            val distance = component.distanceTo(tapPoint)
            val shapeScore = 80.0 - abs(aspect - 2.05) * 20.0
            val score = component.area / 120.0 +
                shapeScore +
                if (component.contains(tapPoint)) 140.0 else 0.0 -
                distance * 0.42

            if (best == null || score > best.score) {
                best = component.copy(score = score)
            }
        }
        return best
    }

    private fun isTrackPixel(color: Int): Boolean {
        val alpha = Color.alpha(color)
        val r = Color.red(color)
        val g = Color.green(color)
        val b = Color.blue(color)
        val hsv = rgbToHsv(r, g, b)
        val hue = hsv.hue
        val saturation = hsv.saturation
        val value = hsv.value
        val fleshPink = hue <= 18.0 || hue >= 345.0
        val balancedPink = abs(g - b) <= 42 && r > g && r > b
        return alpha > 180 &&
            r >= 210 &&
            g in 135..215 &&
            b in 125..215 &&
            fleshPink &&
            saturation in 0.10..0.48 &&
            value >= 0.72 &&
            balancedPink &&
            r - max(g, b) >= 10
    }

    private fun isFieldPixel(color: Int): Boolean {
        val alpha = Color.alpha(color)
        val r = Color.red(color)
        val g = Color.green(color)
        val b = Color.blue(color)
        return alpha > 180 &&
            g >= 155 &&
            r in 70..190 &&
            b in 70..190 &&
            g - max(r, b) >= 22
    }

    private fun rgbToHsv(r: Int, g: Int, b: Int): Hsv {
        val rf = r / 255.0
        val gf = g / 255.0
        val bf = b / 255.0
        val maxValue = max(rf, max(gf, bf))
        val minValue = min(rf, min(gf, bf))
        val delta = maxValue - minValue
        val hue = when {
            delta <= 0.0001 -> 0.0
            maxValue == rf -> 60.0 * (((gf - bf) / delta) % 6.0)
            maxValue == gf -> 60.0 * ((bf - rf) / delta + 2.0)
            else -> 60.0 * ((rf - gf) / delta + 4.0)
        }.let { if (it < 0.0) it + 360.0 else it }
        val saturation = if (maxValue <= 0.0001) 0.0 else delta / maxValue
        return Hsv(hue, saturation, maxValue)
    }

    private fun dilate(mask: BooleanArray, width: Int, height: Int) {
        val original = mask.copyOf()
        for (y in 0 until height) {
            for (x in 0 until width) {
                val index = y * width + x
                if (original[index]) continue

                var neighbors = 0
                for (ny in y - 1..y + 1) {
                    for (nx in x - 1..x + 1) {
                        if (nx !in 0 until width || ny !in 0 until height) continue
                        if (original[ny * width + nx]) neighbors++
                    }
                }
                if (neighbors >= 3) mask[index] = true
            }
        }
    }

    private fun componentWidthMeters(
        component: Component,
        pixelToRoutePoint: (Point) -> RoutePoint?,
    ): Double? {
        val left = pixelToRoutePoint(Point(component.minX, component.centerY)) ?: return null
        val right = pixelToRoutePoint(Point(component.maxX, component.centerY)) ?: return null
        return RouteMath.distanceMeters(left, right)
    }

    private fun componentHeightMeters(
        component: Component,
        pixelToRoutePoint: (Point) -> RoutePoint?,
    ): Double? {
        val top = pixelToRoutePoint(Point(component.centerX, component.minY)) ?: return null
        val bottom = pixelToRoutePoint(Point(component.centerX, component.maxY)) ?: return null
        return RouteMath.distanceMeters(top, bottom)
    }

    private fun componentRotationDegrees(
        component: Component,
        centerPixel: Point,
        center: RoutePoint,
        pixelToRoutePoint: (Point) -> RoutePoint?,
    ): Double? {
        val screenAngle = component.majorAxisScreenRadians
        val axisLengthPixels = (max(component.width, component.height) * 0.32).coerceIn(24.0, 120.0)
        val dx = cos(screenAngle) * axisLengthPixels
        val dy = sin(screenAngle) * axisLengthPixels
        val pointA = pixelToRoutePoint(Point((centerPixel.x + dx).toInt(), (centerPixel.y + dy).toInt())) ?: return null
        val pointB = pixelToRoutePoint(Point((centerPixel.x - dx).toInt(), (centerPixel.y - dy).toInt())) ?: return null
        val projection = com.example.locationmocker.domain.track.TrackRoutePlanner.LocalProjection(center)
        val projectedA = projection.project(pointA)
        val projectedB = projection.project(pointB)
        val angle = atan2(projectedA.y - projectedB.y, projectedA.x - projectedB.x) * 180.0 / Math.PI
        return normalizeAxisDegrees(angle)
    }

    private fun normalizeAxisDegrees(degrees: Double): Double {
        var normalized = degrees % 180.0
        if (normalized < 0.0) normalized += 180.0
        return normalized
    }

    private fun axisAlignmentDeviationDegrees(degrees: Double): Double {
        val normalized = normalizeAxisDegrees(degrees)
        return min(min(abs(normalized), abs(normalized - 90.0)), abs(180.0 - normalized))
    }

    private data class Component(
        val area: Int,
        val minX: Int,
        val minY: Int,
        val maxX: Int,
        val maxY: Int,
        val centroidX: Int,
        val centroidY: Int,
        val covarianceXX: Double,
        val covarianceYY: Double,
        val covarianceXY: Double,
        val score: Double = 0.0,
    ) {
        val width: Int get() = maxX - minX + 1
        val height: Int get() = maxY - minY + 1
        val centerX: Int get() = (minX + maxX) / 2
        val centerY: Int get() = (minY + maxY) / 2
        val aspectRatio: Double get() = max(width, height).toDouble() / max(1, min(width, height))
        val majorAxisScreenRadians: Double
            get() = 0.5 * atan2(2.0 * covarianceXY, covarianceXX - covarianceYY)

        fun contains(point: Point): Boolean {
            return point.x in minX..maxX && point.y in minY..maxY
        }

        fun distanceTo(point: Point): Double {
            return hypot((centerX - point.x).toDouble(), (centerY - point.y).toDouble())
        }
    }

    private data class Hsv(
        val hue: Double,
        val saturation: Double,
        val value: Double,
    )

    private const val FIELD_TAP_TOLERANCE_PIXELS = 80.0
}
