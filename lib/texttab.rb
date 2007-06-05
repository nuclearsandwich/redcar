
module Gtk
  class TextBuffer
#     signal_new("inserted_text",     # name
#            GLib::Signal::RUN_FIRST, # flags
#            nil,                     # accumulator (XXX: not supported yet)
#            nil,                     # return type (void == nil)
#            Gtk::TextIter,
#            String,
#            Fixnum
#            )
  end
  
  class TextIter
    def forward_cursor_position!
      self.forward_cursor_position
      self
    end
    
    def backward_cursor_position!
      self.backward_cursor_position
      self
    end
  end
end
  
module Redcar          
  TextLoc = Struct.new(:line, :offset)
  
  class TextLoc
    def copy
      TextLoc.new(self.line, self.offset)
    end
    
    def <(other)
      if self.line < other.line
        return true
      elsif self.line == other.line
        if self.offset < other.offset
          return true
        else
          return false
        end
      else
        return false
      end
    end
    
    def >(other)
      if self.line > other.line
        return true
      elsif self.line == other.line
        if self.offset > other.offset
          return true
        else
          return false
        end
      else
        return false
      end
    end
    
    def <=(other)
      if self.line < other.line
        return true
      elsif self.line == other.line
        if self.offset < other.offset
          return true
        elsif self.offset == other.offset
          return true
        else
          return false
        end
      else
        return false
      end
    end
    
    def >=(other)
      if self.line > other.line
        return true
      elsif self.line == other.line
        if self.offset > other.offset
          return true
        elsif self.offset == other.offset
          return true
        else
          return false
        end
      else
        return false
      end
    end
  end

  class TextTab < Tab
    include Redcar::Undoable
    include Keymap
    include DebugPrinter
    
    keymap "ctrl a",     :cursor=, :line_start
    keymap "ctrl e",     :cursor=, :line_end
    keymap "ctrl-alt a", :cursor=, :tab_start
    keymap "ctrl-alt e", :cursor=, :tab_end
    keymap "Left",   :left
    keymap "Right",  :right
    keymap "Up",     :up
    keymap "Down",   :down
    keymap "shift Left",  :shift_left
    keymap "shift Right", :shift_right
    keymap "shift Up",    :shift_up
    keymap "shift Down",  :shift_down
    keymap "ctrl z",     :undo
    keymap "ctrl x",     :cut
    keymap "ctrl c",     :copy
    keymap "ctrl v",     :paste
    keymap "ctrl s",     :save
    keymap "ctrl t",     :transpose
    keymap "Delete",     :del
    keymap "BackSpace",  :backspace
    keymap "Space",      :insert_at_cursor,  " "
    keymap "Tab",        :insert_at_cursor,  " "*(Redcar.tab_length||=2)
    keymap "Return",      :return
    keymap /^(.)$/,       :insert_at_cursor, '\1'
    keymap /^shift (.)$/, :insert_at_cursor, '\1'
    keymap /^caps (.)$/,  :insert_at_cursor, '\1'
    keymap "ctrl d",     :print_command_history
    
    attr_accessor :filename, :buffer
    
    # ------ User commands
    
    user_commands do
      def cursor=(offset)
        to_undo :cursor=, cursor_offset
        case offset
        when :line_start
          offset = @buffer.get_iter_at_line(iter(cursor_mark).line).offset
        when :line_end
          offset = @buffer.get_iter_at_line(iter(cursor_mark).line+1).offset-1
        when :tab_start
          offset = 0
        when :tab_end
          offset = length
        else
          true
        end
        @buffer.place_cursor(iter(offset))
        @textview.scroll_mark_onscreen(cursor_mark)
      end
      
      # the undo actions for these are not quite right
      def left
        self.cursor = [cursor_offset - 1, 0].max
      end
      
      def right
        self.cursor = [cursor_offset + 1, length].min
      end
      
      def up
        self.cursor = above_offset(cursor_offset)
      end
      
      def down
        self.cursor = below_offset(cursor_offset)
      end
      
      def shift_left
        @buffer.move_mark(cursor_mark, iter(cursor_mark).backward_cursor_position!)
      end
      
      def shift_right
        @buffer.move_mark(cursor_mark, iter(cursor_mark).forward_cursor_position!)
      end
      
      def shift_up
        @buffer.move_mark(cursor_mark, iter(above_offset(cursor_offset)))
      end
      
      def shift_down
        @buffer.move_mark(cursor_mark, iter(below_offset(cursor_offset)))
      end
      
      def cut
        Clipboard << selection unless selection == ""
        delete_selection
      end
      
      def copy
        Clipboard << selection unless selection == ""
      end
      
      def paste
        delete_selection
        insert_at_cursor Clipboard.top
      end
      
      def backspace
        if selected?
          delete_selection
        else
          delete(cursor_offset-1, cursor_offset)
        end
      end
      
      def del
        if selected?
          delete_selection
        else
          delete(cursor_offset, cursor_offset+1)
        end
      end
      
      def delete_selection
        if selected?
          delete(cursor_offset, selection_offset)
        end
      end
      
      def insert_at_cursor(str)
        insert(cursor_offset, str)
      end
      
      def return
        current_indent = get_line.match(/^\s+/).to_s.gsub("\n", "").length
        p current_indent
        insert_at_cursor("\n"+" "*current_indent)
      end
      
      def length
        @buffer.char_count
      end
      
      def to_s
        @buffer.text
      end
      
      def modified=(val)
        to_undo :modified=, modified?
        @buffer.modified = val
        Redcar.event :tab_modified, self
        @was_modified = val
      end
      
      def select(from, to)
        Redcar.event :select, self
        to_undo :cursor=, cursor_offset
        @buffer.move_mark(cursor_mark, iter(to))
        @buffer.move_mark(selection_mark, iter(from))
        @textview.scroll_mark_onscreen(cursor_mark)
      end
      
      def [](obj)
        case obj.class.to_s
        when "Fixnum", "Bignum", "Integer"
          @buffer.text.at(obj)
        when "Range"
          @buffer.text[obj]
        end
      end
      
      def []=(obj, str)
        case obj.class.to_s
        when "Fixnum", "Bignum", "Integer"
          old = self[obj]
          delete(obj, obj+1)
          insert(obj, str)
        when "Range"
          delete(obj.first, obj.last+1)
          insert(obj.first, str)
        end
      end
      
      def contents=(str)
        replace(str)
      end
      
      def replace(str)
        delete(0, self.length)
        insert(0, str)
      end
      
      def insert(offset, str)
        offset = iter(offset).offset
        to_undo :delete, offset, str.length+offset, str
        @buffer.insert(iter(offset), str)
#         @buffer.signal_emit("inserted_text", iter(offset), 
#                             str, str.length)
      end
      
      def delete(from, to, text="")
        from = iter(from).offset
        to = iter(to).offset
        to_undo :cursor=, cursor_offset
        text = @buffer.get_slice(iter(from), iter(to))
        @buffer.delete(iter(from), iter(to))
        to_undo :insert, from, text
        text
      end
      
      def find_next(str)
        rest = self.contents[(cursor_offset+1)..-1]
        return nil unless rest
        if md = rest.match(/#{str}/)
          p md.offset(0).map{|e| e+cursor_offset+1}
          select(*(md.offset(0).map{|e| e+cursor_offset+1}))
          true
        else
          nil
        end
      end
    end
    
    def replace_selection(text=nil)
      current_text = self.selection
      startsel, endsel  = self.selection_bounds
      self.delete_selection
      if text==nil
        if block_given?
          new_text = yield(current_text.chars)
        end
      else
        new_text = text
      end
      self.insert_at_cursor(new_text)
      self.select(startsel, startsel+new_text.length)
    end
    
    def replace_line(text=nil)
      current_text = self.get_line
      current_cursor = cursor_offset
      startsel, endsel = self.selection_bounds
      self.delete(line_start(cursor_line), 
                  line_end(cursor_line))
      if text==nil
        if block_given?
          new_text = yield(current_text.chars)
        end
      else
        new_text = text
      end
      self.insert(line_start(cursor_line).offset, new_text)
      self.cursor = current_cursor
      self.select(startsel, endsel)
    end
    
    def modified?
      @buffer.modified?
    end
      
    def iter(thing)
      case thing
      when Integer
        thing = [0, thing].max
        thing = [length, thing].min
        @buffer.get_iter_at_offset(thing)
      when Gtk::TextMark
        @buffer.get_iter_at_mark(thing)
      when Gtk::TextIter
        thing
      when TextLoc
        line_start = @buffer.get_iter_at_line(thing.line)
        iter(line_start.offset+thing.offset)
      end
    end
    
    def iter_at_line(num)
      return iter(end_mark) if num == line_count
      @buffer.get_iter_at_line(num)
    end
    
    def line_start(num)
      iter_at_line(num)
    end
    
    def line_end(num)
      if num >= line_count - 1
        iter(end_mark)
      else
        iter_at_line(num+1)
      end
    end
    
    def get_line(num=nil)
      if num == nil
        return get_line(cursor_line)
      end
      if num == @buffer.line_count-1
        end_iter = iter(end_mark)
      elsif num > @buffer.line_count-1
        return nil
      elsif num < 0
        if num >= -@buffer.line_count
          return get_line(@buffer.line_count+num).chars
        else
          return nil
        end
      else
        end_iter = iter_at_line(num+1)
      end
      @buffer.get_slice(iter_at_line(num), end_iter).chars
    end
    
    def get_lines(selector)
      if selector.is_a? Range
        st = selector.begin
        en = selector.end
        if st < 0
          nst = @buffer.line_count+st
        else
          nst = st
        end
        if en < 0
          nen = @buffer.line_count+en
        else
          nen = en
        end
        a = [nst, nen].sort
        selector = a[0]..a[1]
      end
      selector.map{|num| get_line(num)}
    end
    
    def line_count
      @buffer.line_count
    end
    
    def char_count
      @buffer.char_count
    end
    
    def cursor_mark
      @buffer.get_mark("insert")
    end
    
    def cursor_line
      iter(cursor_mark).line
    end
    
    def cursor_offset
      iter(cursor_mark).offset
    end
    
    def cursor_line_offset
      iter(cursor_mark).line_offset
    end
    
    def selection_mark
      @buffer.get_mark("selection_bound")
    end
    
    def selection_offset
      iter(selection_mark).offset
    end
    
    def start_mark
      @buffer.get_mark("start-mark") or
        @buffer.create_mark("start-mark", iter(0), true)
    end
    
    def end_mark
      @buffer.get_mark("end-mark") or
        @buffer.create_mark("end-mark", iter(self.length), false)
    end
    
    def above_offset(offset)
      above_line_num = [iter(offset).line-1, 0].max
      return 0 if above_line_num == 0
      [
       @buffer.get_iter_at_line(above_line_num).offset + 
         [iter(offset).line_offset, get_line(above_line_num).length-1].min,
       0
      ].max
    end
    
    def below_offset(offset)
      below_line_num = iter(offset).line+1
      return char_count-1 if below_line_num == line_count
      [
       @buffer.get_iter_at_line(below_line_num).offset + 
         [iter(offset).line_offset, get_line(below_line_num).length-1].min,
       length
      ].min
    end
    
    def selected?
      start_iter, end_iter, bool = @buffer.selection_bounds
      bool
    end
    
    def selection_bounds
      start_iter, end_iter, bool = @buffer.selection_bounds
      return start_iter.offset, end_iter.offset
    end
    
    def selection
      @buffer.get_text(iter(selection_mark), iter(cursor_mark))
    end
    
    def contents
      @buffer.text
    end
    
    undo_composable do |a, b|
      # break up inserts by words, not characters
      if a.method_name == :insert and
          b.method_name == :insert and
          b.args[1].length == 1 and
          b.args[0] == a.args[0] and
          !(b.args[1] != " " and a.args[1].last == " ")
        c=UndoItem.new(:insert, [b.args[0], a.args[1]+b.args[1]])
        c
      end
    end
    
    undo_composable do |a, b|
      # add a delete onto another delete (corresponds to the delete action),
      # breaking up on words
      if a.method_name == :delete and
          b.method_name == :delete and
          a.args[1] == b.args[0] and
          b.args[2].first != " "
        c=UndoItem.new(:delete, [a.args[0], b.args[1], a.args[2]+b.args[2]])
        c
      end
    end
    
    undo_composable do |a, b|
      # add a delete onto another delete (composing spaces)
      if a.method_name == :delete and
          b.method_name == :delete and
          a.args[1] == b.args[0] and
          a.args[2].last == " " and 
          b.args[2] == " "
        c=UndoItem.new(:delete, [a.args[0], b.args[1], a.args[2]+b.args[2]])
        c
      end
    end
    
    # --------
    
    def initialize(pane)
      Gtk::RC.parse_string(<<-EOR)
  style "green-cursor" {
    GtkTextView::cursor-color = "grey"
  }
  class "GtkWidget" style "green-cursor"
  EOR
#       @tag_table = Gtk::SourceTagTable.new
      @textview = Gtk::SourceView.new()# @tag_table)
      @textview.wrap_mode = Gtk::TextTag::WRAP_WORD
      @textview.show_line_numbers = 1
      @buffer = @textview.buffer
      new_buffer
#       @textview = Redcar::GUI::Text.new(buffer, textview)
      self.set_font("Monospace 11")
      super(pane, @textview)
      Redcar.tab_length ||= 2
      connect_signals
    end
  
  def new_buffer
    text = @buffer.text
    @buffer = Gtk::SourceBuffer.new
    @textview.buffer = @buffer
    @buffer.check_brackets = false
    @buffer.highlight = true
    @buffer.max_undo_levels = 0
    @buffer.text = text
  end
    
    
    def focus
      super
      @textview.grab_focus
    end

    def connect_signals
      @textview.signal_connect('focus-in-event') do |widget, event|
        Redcar.current_pane = self.pane
        Redcar.current_tab = self
        Redcar.event :tab_focus, self
        false
      end
      @was_modified = false
      @buffer.signal_connect("changed") do |widget, event|
        Redcar.event :tab_modified, self unless @was_modified
        Redcar.event :tab_changed
        @was_modified = true
      end
      
      @buffer.signal_connect("mark_set") do |widget, event|
        mark = @buffer.get_mark('insert')
        iter = @buffer.get_iter_at_mark(mark)
        Redcar.event :tab_changed
        
        Redcar.StatusBar.main = "" unless Time.now - Redcar.StatusBar.main_time < 5
        Redcar.StatusBar.sub = "line "+ (iter.line+1).to_s + "   col "+(iter.line_offset+1).to_s
      end
      # eat right button clicks:
      @textview.signal_connect("button_press_event") do |widget, event|
        Redcar.current_tab = self
        Redcar.current_pane = self.pane
        if event.kind_of? Gdk::EventButton 
          Redcar.event :tab_clicked, self
          if event.button == 3
            Redcar.context_menus[self.class.to_s].popup(nil, nil, event.button, event.time)
          end
        end
      end
    end
    
    def set_font(font)
      @textview.modify_font(Pango::FontDescription.new(font))
    end
    
    def load
      Redcar.event :load, self do
        if @filename
          self.replace(Redcar::RedcarFile.load(@filename))
        else
          p :no_filename_to_load_into_tab
        end
      end
    end
    
    def save
      Redcar.event :save, self do
        self.save!
      end
    end
    
    def save!
      if @filename
        Redcar::RedcarFile.save(@filename, self.to_s)
      end
      @buffer.modified = false
    end
    
    
    def close
      pane = self.pane
      if self.modified?
        ask_and_save_tab(self)
      else
        self.close!
      end
    end
  end
end

def ask_and_save_tab(tab)
  tab.focus
  dialog = Redcar::Dialog.build(:title => "Save?",
                                :buttons => [:Save, :Discard, :Cancel],
                                :message => "Tab modified. Save or discard?")
  dialog.on_button(:Save) do
    dialog.close
    tab.save
    unless tab.modified?
      tab.close!
    end
  end
  dialog.on_button(:Discard) do
    dialog.close
    tab.close!
  end
  dialog.on_button(:Cancel) do
    dialog.close
  end
  dialog.show :modal => true
end
  
