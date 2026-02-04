
/************************************************************************
 * @description: JSON library for AutoHotkey v2
 * @author: thqby, modified for QuickSay
 * @date: 2024/02/03
 * @version: 1.0.2
 ***********************************************************************/

class JSON {
	static null := ComValue(1, 0), true := ComValue(0xB, 1), false := ComValue(0xB, 0)

	/**
	 * Parses a JSON string into an AHK Map or Array
	 */
	static Parse(str) {
		if !IsSet(str) || str == ""
			return ""
			
		; Remove BOM if present
		if SubStr(str, 1, 1) = Chr(0xFEFF)
			str := SubStr(str, 2)
			
		pos := 0, len := StrLen(str)
		
		; Skip whitespace
		skip() {
			while (pos < len) {
				pos += 1
				char := SubStr(str, pos, 1)
				if (Ord(char) > 32)
					return char
			}
			return ""
		}
		
		; Parse string
		parse_string() {
			is_escaped := false
			val := ""
			
			; Skip the opening quote
			; pos is currently AT the opening quote due to skip() or logic
			
			loop {
				pos += 1
				if (pos > len)
					throw Error("JSON Parse Error: Unexpected end of string")
					
				char := SubStr(str, pos, 1)
				
				if (is_escaped) {
					switch char {
						case '"': val .= '"'
						case '\': val .= '\'
						case '/': val .= '/'
						case 'b': val .= "`b"
						case 'f': val .= "`f"
						case 'n': val .= "`n"
						case 'r': val .= "`r"
						case 't': val .= "`t"
						case 'u': 
							pos += 1
							val .= Chr("0x" . SubStr(str, pos, 4))
							pos += 3
						default: val .= char
					}
					is_escaped := false
				} else {
					if (char == '\') {
						is_escaped := true
					} else if (char == '"') {
						return val
					} else {
						val .= char
					}
				}
			}
		}
		
		; Parse number
		parse_number(first_char) {
			val := first_char
			loop {
				next_char := SubStr(str, pos + 1, 1)
				if InStr("0123456789+-.eE", next_char) {
					val .= next_char
					pos += 1
				} else {
					break
				}
			}
			return IsNumber(val) ? (InStr(val, ".") || InStr(val, "e") ? Float(val) : Integer(val)) : 0
		}
		
		; Parse value
		parse_value(char) {
			if (char == "{") {
				obj := Map()
				first := true
				loop {
					char := skip()
					if (char == "")
						throw Error("JSON Parse Error: Unexpected end of object")
					if (char == "}")
						return obj
					
					if (!first) {
						if (char == ",") {
							char := skip()
						} else {
							throw Error("JSON Parse Error: Expected ',' or '}' but got " char)
						}
					}
					
					; Key must be string
					if (char != '"')
						throw Error("JSON Parse Error: Expected string key but got " char)
					
					key := parse_string()
					
					char := skip()
					if (char != ":")
						throw Error("JSON Parse Error: Expected ':' but got " char)
						
					val_char := skip()
					obj[key] := parse_value(val_char)
					first := false
				}
			} else if (char == "[") {
				arr := []
				first := true
				loop {
					char := skip()
					if (char == "")
						throw Error("JSON Parse Error: Unexpected end of array")
					if (char == "]")
						return arr
					
					if (!first) {
						if (char == ",") {
							char := skip()
						} else {
							throw Error("JSON Parse Error: Expected ',' or ']' but got " char)
						}
					}
					
					arr.Push(parse_value(char))
					first := false
				}
			} else if (char == '"') {
				return parse_string()
			} else if (InStr("0123456789-", char)) {
				return parse_number(char)
			} else if (char == "t") {
				pos += 3 ; rue
				return 1 ; true
			} else if (char == "f") {
				pos += 4 ; alse
				return 0 ; false
			} else if (char == "n") {
				pos += 3 ; ull
				return "" ; null
			}
			
			throw Error("JSON Parse Error: Unexpected character " char " at pos " pos)
		}
		
		return parse_value(skip())
	}

	/**
	 * Stringifies an AHK Map/Array/Value to JSON string
	 */
	static Stringify(obj, space := "") {
		if !IsSet(obj)
			return "null"
		
		is_arr := Type(obj) = "Array"
		is_map := Type(obj) = "Map"
		
		; String Escape
		if (Type(obj) = "String") {
			str := StrReplace(obj, "\", "\\")
			str := StrReplace(str, "`n", "\n")
			str := StrReplace(str, "`r", "\r")
			str := StrReplace(str, "`t", "\t")
			str := StrReplace(str, "`b", "\b")
			str := StrReplace(str, "`f", "\f")
			str := StrReplace(str, '"', '\"')
			return '"' str '"'
		}
		
		; Numbers
		if (Type(obj) = "Integer" || Type(obj) = "Float")
			return obj
            
        ; COM Objects (null, true, false)
        if (Type(obj) = "ComValue") {
             vt := ComObjType(obj)
             val := Number(obj)
             if (vt = 0xB) ; Boolean
                return val ? "true" : "false"
             if (vt = 1) ; Null
                return "null"
             return val
        }
		
		; Array
		if (is_arr) {
			if (obj.Length = 0)
				return "[]"
			
			res := ""
			indent := space ? "`n" space : ""
			sub_indent := space ? space "  " : ""
			
			for v in obj
				res .= (res ? "," : "") indent JSON.Stringify(v, sub_indent)
			
			return "[" res (space ? "`n" space : "") "]"
		}
		
		; Map or Object
		if (is_map || IsObject(obj)) {
			is_obj_empty := true
			if is_map {
				if obj.Count > 0
					is_obj_empty := false
			} else {
				for k, v in obj.OwnProps() {
					is_obj_empty := false
					break
				}
			}
			
			if is_obj_empty
				return "{}"
			
			res := ""
			indent := space ? "`n" space : ""
			sub_indent := space ? space "  " : ""
			
			if is_map {
				for k, v in obj
					res .= (res ? "," : "") indent JSON.Stringify(String(k)) ":" (space ? " " : "") JSON.Stringify(v, sub_indent)
			} else {
				for k, v in obj.OwnProps()
					res .= (res ? "," : "") indent JSON.Stringify(String(k)) ":" (space ? " " : "") JSON.Stringify(v, sub_indent)
			}
			
			return "{" res (space ? "`n" space : "") "}"
		}
		
		return "null"
	}
}
