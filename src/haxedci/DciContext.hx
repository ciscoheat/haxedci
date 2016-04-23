package haxedci;

import haxe.macro.Expr;
import haxe.macro.Type;

class DciContext {
	public var name(get, never) : String;
	public var cls(default, null) : ClassType;
	public var fields(default, null) : Array<Field> = [];
	public var roles(default, null) : Array<DciRole> = [];
	
	function get_name() return cls.name;

	public function new(cls : ClassType, fields : Array<Field>, roles : Array<DciRole>) {
		if (cls == null) throw "class was null";
		if (fields == null) throw "fields was null";
		if (roles == null) throw "roles was null";
		for (f in fields) if (f == null) throw "a field was null.";
		for (r in roles) if (r == null) throw "a role was null.";
		
		this.cls = cls;
		this.fields = fields;
		this.roles = roles;		
	}
}

class DciRole {
	public var name(get, never) : String;
	public var field(default, null) : Field;
	public var roleMethods(default, null) : Iterable<DciRoleMethod>;
	public var bound(default, default) : Null<Position>;
	public var contract(default, null) : Array<Field>;
	
	function get_name() return field.name;

	public function new(field : Field, roleMethods : Iterable<DciRoleMethod>) {
		if (field == null) throw "field was null";
		if (field.kind.getName() != "FVar") throw "field wasn't a var";
		if (roleMethods == null) throw "roleMethods was null";
		for (r in roleMethods) if (r == null) throw "a roleMethod was null.";

		// FVar(ComplexType(Array<Field>))
		var fieldType : ComplexType = switch field.kind {
			case FVar(t, _): t;
			case _: null;
		}

		if (fieldType.getName() != "TAnonymous") throw "contract wasn't TAnonymous";
		
		this.contract = switch fieldType {
			case TAnonymous(fields): fields;
			case _: null;
		}

		this.field = {
			pos: field.pos,
			name: field.name,
			meta: null,
			kind: FVar(fieldType, null), // Important to set expr to null, to remove the body code
			doc: null,
			access: [APrivate]
		};
		
		this.roleMethods = roleMethods;
	}
}

class DciRoleMethod {
	public var name(default, null) : String;
	public var method(default, null) : Function;
	
	public function new(name : String, method : Function) {
		if (name == null) throw "name was null";
		if (method == null) throw "method was null";
		
		this.name = name;
		this.method = method;
	}	
}
