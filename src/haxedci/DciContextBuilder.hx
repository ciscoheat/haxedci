package haxedci;

#if macro
import haxe.macro.Type.ClassType;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxedci.DciContext.DciRole;
import haxedci.DciContext.DciRoleMethod;

using Lambda;
using StringTools;
using haxe.macro.ExprTools;

class DciContextBuilder
{
	public static var allowThisInRoleMethods = false;
	public static var publicRoleAccess = false;
	
	public static function build() : Array<Field> {
		var contextFields = Context.getBuildFields();
		
		var cls = Context.getLocalClass().get();		
		if (cls == null) throw "Context.getLocalClass() was null";
		
		// A Context cannot be extended.
		cls.meta.add(":final", [], cls.pos);

		// Create the Context
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
		
		var context = new DciContext(
			cls,
			contextFields.filter(function(f) return !isRoleField(f)),
			contextFields.filter(isRoleField).map(fieldToRole.bind(cls))
		);
		
		/*
		trace('===== Context ' + cls.name + ' =================');
		trace('Fields: ' + context.fields.map(function(f) return f.name));
		for (role in context.roles) {
			trace('Role: ' + role.name + ' ' + role.contract.map(function(r) return r.name));
			trace("\\-- " + role.roleMethods.map(function(rm) return rm.name));
		}
		*/
		
		var displayMode = Context.defined("display");

		// Rewrite RoleMethod calls (destination.deposit -> destination__desposit)
		new RoleMethodReplacer(context).replaceAll();
		
		var outputFields = context.fields.concat(context.roles.map(function(role) return role.field));
		var foundAutocompletion = false;
		
		// Create fields for the RoleMethods
		for (role in context.roles) for (roleMethod in role.roleMethods) {
			outputFields.push({
				pos: roleMethod.method.expr.pos,
				name: role.name + '__' + roleMethod.name,
				// TODO: Breaks autocompletion inside RoleMethods 
				//meta: [{ pos: roleMethod.method.expr.pos, params: [], name: ":noCompletion" }],
				meta: null,
				kind: FFun(roleMethod.method),
				doc: null,
				access: [APrivate]
			});			
		}
		
		if (!displayMode) {	
			// After all replacement is done, test if all roles are bound.
			for (r in context.roles) if(r.bound == null) {
				Context.warning("Role " + r.name + " isn't bound in its Context.", r.field.pos);
			}
		} else {
			//Autocompletion.fileTrace(contextData(context));
		}
				
		return outputFields;
	}

	static function fieldToRole(cls : ClassType, field : Field) : DciRole {
		function incorrectTypeError() {
			Context.error("A Role must have an anonymous structure as its contract. " +
				"See http://haxe.org/manual/types-anonymous-structure.html for syntax.", field.pos);
		}
		function basicTypeError(name) {
			Context.error(name + " is a basic type (Int, Bool, Float, String), only objects can play a Role in a Context. " + 
				"You can make it a normal field instead, or pass it as a parameter.", field.pos);
		}
		
		return switch field.kind {
			case FVar(t, e):
				if (t == null) incorrectTypeError();
				if (e != null) Context.error(
					"RoleMethods using the \"} = {\" syntax is deprecated. " + 
					"Remove it and set the affected RoleMethods to public.", e.pos
				);

				var roleMethods : Array<DciRoleMethod> = [];
				var contract : Array<Field> = [];

				switch(t) {
					case TAnonymous(fields): 
						var keep = [];
						for (f in fields) switch f.kind {
							case FFun(fun) if (fun.expr != null):
								roleMethods.push(new DciRoleMethod(f.name, fun, f.access.has(APublic)));
							case _:
								keep.push(f);
						}
						// Remove roleMethods (functions with body)
						field.kind = FVar(TAnonymous(keep), e);

					case TPath( { name: "Int", pack: [], params: [] } ): basicTypeError("Int");
					case TPath( { name: "Bool", pack: [], params: [] } ): basicTypeError("Bool");
					case TPath( { name: "Float", pack: [], params: [] } ): basicTypeError("Float");
					case TPath( { name: "String", pack: [], params: [] } ): basicTypeError("String");
						
					case _: incorrectTypeError();
				}
				
				new DciRole(cls.pack, cls.name, field, roleMethods, contract);
				
			case _: 
				Context.error("Only var fields can be a Role.", field.pos);
		}
	}
	
	public static function contextData(context : DciContext) {
		return "===== " + context.name + "\n" +
		context.roles.map(function(role)
			return role.name + " " + 
			role.contract.map(function(c) return c.name) 
			+ role.roleMethods.map(function(rm) return rm.name)
		).join("\n");
	}
}
#end
