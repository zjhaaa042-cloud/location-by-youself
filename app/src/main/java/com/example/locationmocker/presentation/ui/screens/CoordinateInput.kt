package com.example.locationmocker.presentation.ui.screens

import com.example.locationmocker.domain.model.RoutePoint

data class CoordinateInputResult(
    val point: RoutePoint? = null,
    val error: String? = null,
)

fun parseCoordinateInput(raw: String): CoordinateInputResult {
    val values = raw
        .trim()
        .replace('，', ',')
        .split(Regex("[,\\s]+"))
        .filter { it.isNotBlank() }

    if (values.size != 2) {
        return CoordinateInputResult(error = "请输入“纬度, 经度”，例如 39.9042, 116.4074")
    }

    val latitude = values[0].toDoubleOrNull()
    val longitude = values[1].toDoubleOrNull()
    if (latitude == null || longitude == null) {
        return CoordinateInputResult(error = "坐标只能包含数字、小数点、负号和分隔符")
    }
    if (latitude !in -90.0..90.0) {
        return CoordinateInputResult(error = "纬度应在 -90 到 90 之间")
    }
    if (longitude !in -180.0..180.0) {
        return CoordinateInputResult(error = "经度应在 -180 到 180 之间")
    }

    return CoordinateInputResult(point = RoutePoint(lat = latitude, lon = longitude))
}
