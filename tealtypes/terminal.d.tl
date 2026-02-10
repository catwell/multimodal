local record terminal
   type TextAttr = {string: string | integer | boolean}

   record Output
      write: function(...: any)
      flush: function()
   end
   output: Output

   record CursorPosition
      set: function(row: integer, column: integer): boolean
   end

   record CursorVisible
      set: function(visible: boolean): boolean
   end

   record Cursor
      position: CursorPosition
      visible: CursorVisible
   end
   cursor: Cursor

   record Clear
      screen: function(): boolean
      line: function(): boolean
      eol: function(): boolean
   end
   clear: Clear

   record TextStack
      push: function(attr: TextAttr): boolean
      pop: function(n: integer): boolean
      apply: function(): boolean
   end

   record Text
      attr: function(attr: TextAttr): boolean
      stack: TextStack
   end
   text: Text

   record KeyMap
      default_key_map: {string: string}
      default_keys: {string: string}
   end

   record Input
      readansi: function(timeout: number): string, string, string
      keymap: KeyMap
   end
   input: Input

   initialize: function(opts: {string: any}): boolean
   shutdown: function(): boolean
   initwrap: function(main: function(), opts: {string: any}): function()
   ready: function(): boolean
   size: function(): integer, integer
end

return terminal
