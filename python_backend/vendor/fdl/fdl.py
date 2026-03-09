from __future__ import annotations

from pydantic import field_serializer

from fdl.canvas import Canvas
from fdl.canvastemplate import CanvasTemplate
from fdl.common import TypedCollection
from fdl.context import Context
from fdl.framingintent import FramingIntent
from fdl.header import Header


class FDL(Header):
    framing_intents: TypedCollection[FramingIntent] = TypedCollection[FramingIntent]()
    contexts: TypedCollection[Context] = TypedCollection[Context]()
    canvas_templates: TypedCollection[CanvasTemplate] = TypedCollection[CanvasTemplate]()

    def place_canvas_in_context(self, context_label: str, canvas: Canvas):
        """Place a canvas in a context. If no context with the provided label exist,
        a new context will be created for you.

        Args:
            context_label: name of existing or to be created context
            canvas: to be placed in context
        """

        context = self.contexts.get_by_id(context_label)
        if context is None:
            context = Context(label=context_label)
            self.contexts.append(context)

        context.canvases.append(canvas)

    @field_serializer("default_framing_intent")
    def _check_default_framing_intent(self, framing_intent_id: str | None) -> str | None:
        if framing_intent_id is None:
            return None

        if self.framing_intents.get_by_id(framing_intent_id) is None:
            raise ValueError(f'Default framing intent: "{framing_intent_id}" is not found among registered framing intents')

        return framing_intent_id

    def validate_fdl(self):
        """Validate the current state of the FDL.

        Routes through the handler system to run both format-specific
        schema validation and semantic validation.

        Raises:
            FDLValidationError: if any errors are found
        """
        from fdl.handlers import validate

        validate(self)
