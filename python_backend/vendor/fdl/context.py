from __future__ import annotations

from pydantic import BaseModel

from fdl import Canvas, ClipID, TypedCollection
from fdl.framingdecision import FramingDecision


class Context(BaseModel):
    label: str | None = None
    context_creator: str | None = None
    clip_id: ClipID | None = None
    canvases: TypedCollection[Canvas] = TypedCollection[Canvas]()

    def resolve_canvas_for_dimensions(
        self,
        input_width: float,
        input_height: float,
        canvas: Canvas,
        framing: FramingDecision,
    ) -> tuple[Canvas, FramingDecision, bool]:
        """Find a matching canvas when input dimensions don't match the selected canvas.

        If the selected canvas dimensions don't match the input dimensions and the canvas
        has a different source_canvas_id, searches other canvases in this context for one
        whose dimensions match and has a framing decision with the same label.

        Parameters
        ----------
        input_width : float
            The input image width.
        input_height : float
            The input image height.
        canvas : Canvas
            The initially selected canvas.
        framing : FramingDecision
            The initially selected framing decision.

        Returns
        -------
        tuple[Canvas, FramingDecision, bool]
            (resolved_canvas, resolved_framing, was_resolved) where was_resolved
            is True if a different canvas was found.

        Raises
        ------
        ValueError
            If dimensions don't match and no alternative canvas is found.
        """
        if canvas.dimensions.width == input_width and canvas.dimensions.height == input_height:
            return canvas, framing, False

        if canvas.id != canvas.source_canvas_id:
            for other_canvas in self.canvases:
                if other_canvas.dimensions.width == input_width and other_canvas.dimensions.height == input_height:
                    for other_fd in other_canvas.framing_decisions:
                        if other_fd.label == framing.label:
                            return other_canvas, other_fd, True

        raise ValueError(
            f"Canvas dimensions ({canvas.dimensions.width}x{canvas.dimensions.height}) "
            f"do not match input dimensions ({input_width}x{input_height})"
        )

    def __eq__(self, other: object) -> bool:
        if isinstance(other, Context):
            return self.label == other.label
        if isinstance(other, str):
            return self.label == other
        return NotImplemented

    def __hash__(self):
        return hash((self.label,))
