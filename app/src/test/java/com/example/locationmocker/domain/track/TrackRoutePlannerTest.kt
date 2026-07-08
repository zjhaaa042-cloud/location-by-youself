package com.example.locationmocker.domain.track

import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.route.RouteMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackRoutePlannerTest {
    private val planner = TrackRoutePlanner()

    @Test
    fun buildCounterClockwiseRoute_returnsClosedRouteNear400Meters() {
        val route = planner.buildCounterClockwiseRoute(RoutePoint(31.2304, 121.4737))

        assertTrue(route.size > 100)
        assertTrue(RouteMath.distanceMeters(route.first(), route.last()) < 0.5)
        val perimeter = route.zipWithNext().sumOf { (a, b) -> RouteMath.distanceMeters(a, b) }
        assertTrue(perimeter in 390.0..410.0)
        assertTrue(signedArea(route) > 0.0)
    }

    @Test
    fun buildCounterClockwiseRoute_keepsProvidedBoundsClosed() {
        val center = RoutePoint(31.2304, 121.4737)
        val route = planner.buildCounterClockwiseRoute(center, sampleBounds(center))

        assertEquals(route.first().lat, route.last().lat, 0.000001)
        assertEquals(route.first().lon, route.last().lon, 0.000001)
    }

    @Test
    fun buildCounterClockwiseRoute_supportsVerticalOrientation() {
        val center = RoutePoint(31.2304, 121.4737)
        val horizontal = planner.buildCounterClockwiseRoute(center, orientation = TrackOrientation.Horizontal)
        val vertical = planner.buildCounterClockwiseRoute(center, orientation = TrackOrientation.Vertical)
        val projection = TrackRoutePlanner.LocalProjection(center)

        val horizontalFirst = projection.project(horizontal.first())
        val verticalFirst = projection.project(vertical.first())

        assertTrue(kotlin.math.abs(horizontalFirst.x) > kotlin.math.abs(horizontalFirst.y))
        assertTrue(kotlin.math.abs(verticalFirst.y) > kotlin.math.abs(verticalFirst.x))
    }

    private fun sampleBounds(center: RoutePoint): List<RoutePoint> {
        val projection = TrackRoutePlanner.LocalProjection(center)
        return listOf(
            projection.unproject(TrackRoutePlanner.ProjectedPoint(50.0, 0.0)),
            projection.unproject(TrackRoutePlanner.ProjectedPoint(0.0, 20.0)),
            projection.unproject(TrackRoutePlanner.ProjectedPoint(-50.0, 0.0)),
            projection.unproject(TrackRoutePlanner.ProjectedPoint(0.0, -20.0)),
            projection.unproject(TrackRoutePlanner.ProjectedPoint(50.0, 0.0)),
            projection.unproject(TrackRoutePlanner.ProjectedPoint(45.0, 5.0)),
        )
    }

    private fun signedArea(points: List<RoutePoint>): Double {
        val projection = TrackRoutePlanner.LocalProjection(points.first())
        val projected = points.map(projection::project)
        return projected.zipWithNext().sumOf { (a, b) -> a.x * b.y - b.x * a.y } / 2.0
    }
}
