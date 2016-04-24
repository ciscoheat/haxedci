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

	var selfType : ComplexType;
	
	public function new(pack : Array<String>, className : String, field : Field, roleMethods : Iterable<DciRoleMethod>) {
		if (pack == null) throw "pack was null";
		if (className == null) throw "className was null";
		if (field == null) throw "field was null";
		if (roleMethods == null) throw "roleMethods was null";
		for (r in roleMethods) if (r == null) throw "a roleMethod was null.";

		// FVar(ComplexType(Array<Field>))
		var fieldType : ComplexType = switch field.kind {
			case FVar(t, _): t;
			case _: null;
		}

		if (fieldType == null || fieldType.getName() != "TAnonymous") throw "contract wasn't TAnonymous";
		
		this.contract = switch fieldType {
			case TAnonymous(fields): fields;
			case _: null;
		}
		
		function testSelfReference(type : Null<ComplexType>) : ComplexType {
			return if (type == null) null
			else switch type {
				case TPath({sub: _, params: _, pack: ["dci"], name: "Self"}) | TPath({sub: _, params: _, pack: [], name: "Self"}):
					if (selfType == null) {
						var classPackage = className.charAt(0).toLowerCase() + className.substr(1);
						var pack = ['dci'].concat(pack).concat([classPackage]);
						var name = field.name;
						
						// Define a custom type, to avoid circular referencing of TAnonymous
						haxe.macro.Context.defineType({
							pos: field.pos,
							params: null,
							pack: pack,
							name: name,
							meta: null,
							kind: TDStructure,
							isExtern: false,
							fields: this.contract
						});
						
						selfType = TPath( { sub: null, params: null, pack: pack, name: name } );
					}
					selfType;
				case _:
					type;
			}
		}
		
		// Test if a field references Self, then change that type to the fieldType
		for (field in this.contract) {
			field.kind = switch field.kind {
				case FVar(type, e): 
					FVar(testSelfReference(type));
				case FFun(f):
					for (arg in f.args) arg.type = testSelfReference(arg.type);
					f.ret = testSelfReference(f.ret);
					FFun(f);
				case FProp(get, set, t, e):
					FProp(get, set, testSelfReference(t), e);
			}
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
