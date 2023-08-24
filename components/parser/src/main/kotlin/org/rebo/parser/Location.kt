package org.rebo.parser

public sealed class Location {
    operator fun plus(other: Location): Location {
        if (this == other) {
            return this
        }

        return when (this) {
            is Position -> when (other) {
                is Position -> Range(this.min(other), this.max(other))
                is Range -> Range(this.min(other.start), this.max(other.end))
            }

            is Range -> when (other) {
                is Position -> Range(this.start.min(other), this.end.max(other))
                is Range -> Range(this.start.min(other.start), other.end.max(other.end))
            }
        }
    }
}

public data class Position(
    public val line: Int,
    public val column: Int,
    public val offset: Int
) : Location() {
    fun min(other: Position): Position {
        if (this.offset < other.offset) {
            return this
        }

        return other
    }

    fun max(other: Position): Position {
        if (this.offset > other.offset) {
            return this
        }

        return other
    }
}

public data class Range(
    public val start: Position,
    public val end: Position
) : Location()