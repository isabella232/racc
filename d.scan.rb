
  class RaccScanner < Scanner

    def reset( str, rac )
      super( str )
      @toktbl = rac.ruletable.tokentable
      @code   = rac.code
    end
    
    # pattern

    COMMENT   = /\A\#[^\n\r]*/o
    BEGIN_C   = /\A\/\*[^\n\r(\*\/)]*/o
    ATOM      = /\A[a-zA-Z_]\w*/o
    CODEBLOCK = /\A(\n|\r\n|\r)\-\-\-\-+/o


    def scan
      while true do
        unless @str.rest? then
          @spipe.push false ; @vpipe.push false 
          @spipe.push false ; @vpipe.push false
          break
        end

        @str.skip SPC
        unless @str.skip COMMENT then
          if @str.skip BEGIN_C then
            scan_comment
            next
          end
        end

        if temp = @str.scan( CODEBLOCK ) then
          @str.unscan
          @str.skip EOL ; @lineno += 1
          scan_usercode
          @str.clear
          next
        end

        if @str.skip EOL then
          @lineno += 1
          next
        end

        if atm = @str.scan( ATOM ) then
          scan_atom( atm )
          break  #next
        end

        case fch = @str.getch
        when '"', "'"
          @spipe.push :STRING
          @vpipe.push scan_string( fch )
        when '{'
          @spipe.push :ACTION
          @vpipe.push scan_action
        else
          @spipe.push fch
          @vpipe.push fch
        end

        break
      end

      debug_report if @debug
    end



    private


    def scan_atom( cur )
      sret = :TOKEN
      vret = @toktbl.get_token( cur.intern )

      case cur
      when 'end'      then sret = :XEND
      when 'token'    then sret = :XTOKEN
      when 'right'    then sret = :RIGHT
      when 'left'     then sret = :LEFT
      when 'nonassoc' then sret = :NONASSOC
      when 'preclow'  then sret = :PRECLOW
      when 'prechigh' then sret = :PRECHIGH
      when 'start'    then sret = :START
      when 'class'    then sret = :CLASS
      when 'rule'     then sret = :RULE
      when 'file'     then sret = :XFILE
      when '$end'     then vret = @toktbl.get_token( Parser::Anchor )
      end

      @spipe.push sret
      @vpipe.push vret
    end


  # BEGIN_C   = /\A\/\*[^\n\r(\*\/)]*/o
    COM_ENT   = /\A[^\n\r*]+/o
    COM_ENT2  = /\A\*+[^*\/\r\n]/o
    END_C     = /\A\*+\//o

    def scan_comment
      while @str.rest? do
        if    @str.skip COM_ENT
        elsif @str.skip COM_ENT2
        elsif @str.skip EOL      then @lineno += 1
        elsif @str.skip END_C    then return
        else
          scan_bug! 'in comment, no exp match'
        end
      end
      scan_error! 'find unterminated comment'
    end


    SKIP         = /\A[^\'\"\`\{\}\/\#\r\n]+/o
    COMMENT_CONT = /\A[^\r\n]*/o

    def scan_action
      ret  = ''
      nest = 0
      while @str.rest? do
        if temp = @str.scan( SKIP ) then
          ret << temp
        end
        if temp = @str.scan( EOL ) then
          ret << temp
          @lineno += 1
          next
        end

        case ch = @str.getch
        when '{'
          nest += 1
          ret << ch

        when '}'
          nest -= 1
          if nest < 0 then
            break
          end
          ret << ch

        when "'", '"', '`'
          ret << ch << scan_string( ch ) << ch

        when '/'
          if SPC === ret[-1,1] then
            if @str.peep(1) != '=' then
              ret << ch << scan_string( ch ) << ch
              next
            end
          end
          ret << ch

        when '#'
          ret << ch << @str.scan( COMMENT_CONT ) << @str.scan( EOL )
          @lineno += 1

        else
          bug! 'must not huppen'
        end
      end

      return ret
    end


    INCLUDE    = /\A\s+\=/o
    BEGINBLOCK = /\A\-\-\-\-+/o

    def scan_usercode
      bname = nil
      ret = ''

      while @str.rest? do
        unless line = @str.scan( LINE ) then        #p @str
          bug! 'in scan_rest, not match'
        end

        if BEGINBLOCK === line then
          if bname then
            @code.store( bname, ret )
            ret = ''
          end
          bname, rest = get_blockname( $' )

          if INCLUDE === rest then
            arr = get_filename( $' )
            load_files( arr, ret, bname )
          end
        else
          ret << line
        end
        @lineno += 1
      end
            
      if bname then
        @code.store( bname, ret )
      end
    end


    BLOCKNAME = /\A[ \t]*(\w+)/o

    def get_blockname( str )
      unless BLOCKNAME === str then
        scan_error! 'missing block name'
      end
      return $1.downcase, $'
    end


    def get_filename( str )
      str.strip!
      return str.split( /[ \t]/o )
    end


    def load_files( arr, ret, bname )
      arr.each do |fname|
        unless File.exist? fname then
          raise NameError, "#{bname} file '#{fname}' does not exist"
        end
        unless File.file? fname then
          raise NameError, "#{bname} file '#{fname}' is not file"
        end
        f = File.open( fname )
        ret << f.read
        f.close

        ret << "\n"  # for safety
      end
    end
      

  end   # RaccScanner

