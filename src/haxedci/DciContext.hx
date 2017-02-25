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
	public var autocomplete(default, default) : DciRoleMethod;
	
	function get_name() return cls.name;

	public function buildFields() : Array<Field> {
		return normalFields.concat(roles.flatMap(function(role) {
			var roleMethodMap = role.roleMethods.array();
			return [role.field].concat(roleMethodMap.map(function(rm) { 
				return rm.field;
			}));
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
				return null;
			}
			function basicTypeError(name) {
				Context.error(name + " is a basic type (Int, Bool, Float, String), only objects can play a Role in a Context. " + 
					"You can make it a normal field instead, or pass it as a parameter.", roleField.pos);
				return null;
			}
			
			return switch roleField.kind {
				case FVar(t, e):
					if (t == null) incorrectTypeError();
					if (e != null) Context.error(
						"RoleMethods using the \"} = {\" syntax is deprecated. " + 
						"Remove it and set the affected RoleMethods to public.", e.pos
					);

					return switch t {
						case TAnonymous(fields): 
							var roleMethods : Array<DciRoleMethod> = [];
							var contract : Array<Field> = [];
							
							for (f in fields) switch f.kind {
								case FFun(fun) if (fun.expr != null):
									var roleMethodField = {
										pos: f.pos,
										name: roleField.name + '__' + f.name,
										// TODO: Breaks autocompletion inside RoleMethods 
										//meta: [{ pos: f.pos, params: [], name: ":noCompletion" }],
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
							
							new DciRole(cls, roleField, roleMethods, contract);

						case TPath( { name: "Int", pack: [], params: [] } ): basicTypeError("Int");
						case TPath( { name: "Bool", pack: [], params: [] } ): basicTypeError("Bool");
						case TPath( { name: "Float", pack: [], params: [] } ): basicTypeError("Float");
						case TPath( { name: "String", pack: [], params: [] } ): basicTypeError("String");
							
						case _: incorrectTypeError();
					}
					
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

	public function new(contextType : ClassType, field : Field, roleMethods : Array<DciRoleMethod>, contract : Array<Field>) {
		// Test for RoleMethod/contract name collisions
		var methods = [for (r in roleMethods) r.name => r];

		for (c in contract) {
			if (methods.exists(c.name)) {
				var r = methods.get(c.name);
				haxe.macro.Context.warning("RoleMethod/contract name collision for field " + r.name, r.method.expr.pos);
				haxe.macro.Context.error("RoleMethod/contract name collision for field " + r.name, c.pos);
			}
		}
		
		// Create type for Role
		// TODO: Don't use in display mode?

		var pack = contextType.pack;
		var name = contextType.name + field.name.charAt(0).toUpperCase() + field.name.substr(1);
		var selfType = TPath( { sub: null, params: null, pack: ["dci"], name: "Self" } );
		var hasSelfType = false;

		// Test if a field references Self, then change that type to the fieldType
		function replaceSelfReference() {
			
			function testSelfReference(type : Null<ComplexType>) : ComplexType {
				return if (type == null) null
				else switch type {
					case TPath( { sub: _, params: _, pack: [], name: "Self" } ) | 
						 TPath({sub: _, params: _, pack: ["dci"], name: "Self"}):
						hasSelfType = true;
						selfType;
					case _:
						type;
				}
			}
			
			for (field in contract) {
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
		}
		
		// The first pass changes "Self" to "dci.Self", because defineType doesn't have access
		// to any imported modules.
		replaceSelfReference();
		
		// Define the RoleObjectContract as a custom type, to avoid circular referencing of TAnonymous
		haxe.macro.Context.defineType({
			pos: field.pos,
			params: null,
			pack: pack,
			name: name,
			meta: null,
			kind: TDStructure,
			isExtern: false,
			fields: contract
		});

		// Reassign selfType, so it can be used in the replacement.
		selfType = TPath( { sub: null, params: null, pack: pack, name: name } );		
		
		// Now when the type is created, we can replace "dci.Self" with the new type.
		if(hasSelfType) replaceSelfReference();
		
		this.field = {
			pos: field.pos,
			name: field.name,
			meta: field.meta,
			kind: FVar(selfType, null),
			//kind: FVar(TAnonymous(contract), null),
			doc: field.doc,
			access: [APrivate]
		};
		
		this.roleMethods = roleMethods;
		this.contract = contract;
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
