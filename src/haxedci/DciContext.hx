package haxedci;

import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Context;

using Lambda;

class DciContext {
	public var name(get, never) : String;
	public var cls(default, null) : ClassType;
	public var normalFields(default, null) : Array<Field> = [];
	public var roles(default, null) : Array<DciRole> = [];
	
	function get_name() return cls.name;

	public function buildFields() : Array<Field> {
		return normalFields.concat(roles.flatMap(function(role) {
			var map = role.roleMethods.map(function(rm) return rm.field);
			return [role.field].concat(map);
		}).array());
	}
	
	public function new(cls : ClassType, buildFields : Array<Field>) {
		this.cls = cls;
		
		// A Context cannot be extended.
		if(!cls.meta.has(":final"))
			cls.meta.add(":final", [], cls.pos);
			
		function isRoleField(field : Field) {
			if (!field.meta.exists(function(m) return m.name == "role")) return false;
			
			var error = function() {
				Context.error("@role can only be used on private, non-static var fields.", field.pos);
				return false;
			}
			
			return switch(field.kind) {
				case FVar(_, _): (field.access.has(AStatic) || field.access.has(APublic)) ? error() : true;
				case _: error();
			}
		}
		
		function fieldToRole(roleField : Field) : DciRole {
			function incorrectTypeError() {
				Context.error("A Role must have an anonymous structure as its contract. " +
					"See http://haxe.org/manual/types-anonymous-structure.html for syntax.", roleField.pos);
			}
			function basicTypeError(name) {
				Context.error(name + " is a basic type (Int, Bool, Float, String), only objects can play a Role in a Context. " + 
					"You can make it a normal field instead, or pass it as a parameter.", roleField.pos);
			}
			
			return switch roleField.kind {
				case FVar(t, e):
					if (t == null) incorrectTypeError();
					if (e != null) Context.error(
						"RoleMethods using the \"} = {\" syntax is deprecated. " + 
						"Remove it and set the affected RoleMethods to public.", e.pos
					);

					var roleMethods : Array<DciRoleMethod> = [];
					var contract : Array<Field> = [];

					switch t {
						case TAnonymous(fields): for (f in fields) switch f.kind {
							case FFun(fun) if (fun.expr != null):
								var roleMethodField = {
									pos: f.pos,
									name: roleField.name + '__' + f.name,
									// TODO: Breaks autocompletion inside RoleMethods 
									//meta: [{ pos: roleMethod.method.expr.pos, params: [], name: ":noCompletion" }],
									meta: null,
									kind: FFun(fun),
									doc: null,
									access: f.access
								};
								
								roleMethods.push(new DciRoleMethod(
									f.name, roleMethodField, f.access != null && f.access.has(APublic)
								));
							case _:
								contract.push(f);
						}

						case TPath( { name: "Int", pack: [], params: [] } ): basicTypeError("Int");
						case TPath( { name: "Bool", pack: [], params: [] } ): basicTypeError("Bool");
						case TPath( { name: "Float", pack: [], params: [] } ): basicTypeError("Float");
						case TPath( { name: "String", pack: [], params: [] } ): basicTypeError("String");
							
						case _: incorrectTypeError();
					}
					
					// Set role type
					roleField.kind = FVar(TAnonymous(contract));
					new DciRole(cls, roleField, roleMethods, contract);
					
				case _: 
					Context.error("Only var fields can be a Role.", roleField.pos);
			}
		}
		
		this.roles = buildFields.filter(isRoleField).map(fieldToRole);
		this.normalFields = buildFields.filter(function(f) return !isRoleField(f));
	}
}

class DciRole {
	public var name(get, never) : String;
	public var field(default, null) : Field;
	public var roleMethods(default, null) : Array<DciRoleMethod>;
	public var bound(default, default) : Null<Position>;
	public var contract(default, null) : Array<Field>;
	
	function get_name() return field.name;

	var selfType : ComplexType;
	
	public function publicApi() : Array<Field> {
		var methods = roleMethods.filter(function(rm) return rm.isPublic).map(function(rm) return rm.field).concat(
			contract.filter(function(f) return f.access != null && f.access.has(APublic))
		);
		return [for (f in methods) {
			var fun : Function = cast f.kind.getParameters()[0];
			{
				access: f.access,
				doc: f.doc,
				kind: FFun({
					args: fun.args,
					expr: null,
					params: fun.params,
					ret: fun.ret
				}),
				meta: f.meta,
				name: f.name,
				pos: f.pos
			}
		}];
	}
	
	public function new(contextType : ClassType, field : Field, roleMethods : Array<DciRoleMethod>, contract : Array<Field>) {

		var fieldType : ComplexType = switch field.kind {
			case FVar(t, _): t;
			case _: null;
		}

		if (fieldType == null || fieldType.getName() != "TAnonymous") throw "contract wasn't TAnonymous";
		
		this.contract = switch fieldType {
			case TAnonymous(fields): contract.concat(fields);
			case _: contract;
		}
		
		// Test for RoleMethod/contract name collisions
		for (r in roleMethods) {
			var contract = this.contract.find(function(c) return c.name == r.name);
			if (contract != null) {
				haxe.macro.Context.warning("RoleMethod/contract name collision for field " + r.name, r.method.expr.pos);
				haxe.macro.Context.error("RoleMethod/contract name collision for field " + r.name, contract.pos);
			}
		}
		
		/*
		function testSelfReference(type : Null<ComplexType>) : ComplexType {
			return if (type == null) null
			else switch type {
				case TPath({sub: _, params: _, pack: ["dci"], name: "Self"}) | TPath({sub: _, params: _, pack: [], name: "Self"}):
					if (selfType == null) {
						var classPackage = contextType.name.charAt(0).toLowerCase() + contextType.name.substr(1);
						var pack = ['dci'].concat(contextType.pack).concat([classPackage]);
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
		for (roleMethod in roleMethods) {
			roleMethod.method.ret = testSelfReference(roleMethod.method.ret);
			for (arg in roleMethod.method.args) arg.type = testSelfReference(arg.type);
		}
		*/
		
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
	public var field(default, null) : Field;
	public var method(get, null) : Function;
	public var isPublic(default, null) : Bool;	
	public var hasDisplay(default, default) : Bool = false;
	
	public function new(name : String, field : Field, isPublic : Bool) {
		this.name = name;
		this.field = field;
		this.isPublic = isPublic;
	}
	
	function get_method() return cast field.kind.getParameters()[0];
}
