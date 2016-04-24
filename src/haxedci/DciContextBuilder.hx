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
	public static var allowExernalRoleContractAccess = false;
	
	public static function build() : Array<Field> {
		var contextFields = Context.getBuildFields();
		
		var cls = Context.getLocalClass().get();		
		if (cls == null) throw "Context.getLocalClass() was null";

		// Create the Context
		var context = new DciContext(
			cls,
			contextFields.filter(function(f) return !isRoleField(f)),
			contextFields.filter(isRoleField).map(fieldToRole.bind(cls))
		);
		
		var displayMode = Context.defined("display");

		// Rewrite RoleMethod calls (destination.deposit -> destination__desposit)
		new RoleMethodReplacer(context).replaceAll();
		
		var outputFields = context.fields.concat(context.roles.map(function(role) return {
			pos: role.field.pos,
			name: role.field.name,
			meta: role.field.meta,
			kind: displayMode ? new Autocompletion(context).fieldKindForRole(role) : role.field.kind,
			doc: role.field.doc,
			access: role.field.access
		}));
		
		// Create fields for the RoleMethods
		for (role in context.roles) for (roleMethod in role.roleMethods) {
			outputFields.push({
				pos: roleMethod.method.expr.pos,
				name: role.name + '__' + roleMethod.name,
				meta: [{ pos: roleMethod.method.expr.pos, params: [], name: ":noCompletion" }],
				kind: FFun(roleMethod.method),
				doc: null,
				access: [APrivate]
			});
		}
		
		if (!displayMode) {	
			// After all replacement is done, test if all roles are bound.
			for (r in context.roles) if(r.bound == null) {
				Context.warning("Role " + r.name + " isn't bound in this Context.", r.field.pos);
			}
		}
				
		return outputFields;
	}

	static function isRoleField(field : Field) {
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

	static function fieldToRole(cls : ClassType, field : Field) : DciRole {
		function incorrectTypeError() {
			Context.error("A Role must have an anonymous structure as its contract. " +
				"See http://haxe.org/manual/types-anonymous-structure.html for syntax.", field.pos);
		}
		function basicTypeError(name) {
			Context.error(name + " is a basic type (Int, Bool, Float), only objects can play a Role in a Context. " + 
				"You can make it a normal field instead, or pass it as a parameter.", field.pos);
		}
		
		return switch field.kind {
			case FVar(t, e):
				if (t == null) incorrectTypeError();

				switch(t) {
					case TAnonymous(fields): // The only correct option

					case TPath( { name: "Int", pack: [], params: [] } ): basicTypeError("Int");
					case TPath( { name: "Bool", pack: [], params: [] } ): basicTypeError("Bool");
					case TPath( { name: "Float", pack: [], params: [] } ): basicTypeError("Float");
						
					case _: incorrectTypeError();
				}
				
				var roleMethods = if(e == null) [] else switch e.expr {
					case EBlock(exprs): 
						exprs.map(function(e) return switch e.expr {
							case EFunction(name, func):
								if (name == null) Context.error("A RoleMethod must have a name.", e.pos);
								new DciRoleMethod(name, func);
							case _:
								Context.error("A Role can only contain functions as RoleMethods.", e.pos);
						});
					case _: 
						Context.error("A Role can only be assigned a block of RoleMethods.", e.pos);
				}
				
				new DciRole(cls.pack, cls.name, field, roleMethods);
				
			case _: 
				Context.error("Only var fields can be a Role.", field.pos);
		}
	}
	
	////////////////////////////////////////////////////////////////////////////////////
	
	// Debugging autocompletion is very tedious, so here's a helper method.
	public static function fileTrace(o : Dynamic, ?file : String)
	{
		file = Context.definedValue("filetrace");
		if (file == null) file = "e:\\temp\\filetrace.txt";
		
		var f : sys.io.FileOutput;
		try f = sys.io.File.append(file, false)
		catch (e : Dynamic) f = sys.io.File.write(file, false);
		f.writeString(Std.string(o) + "\n");
		f.close();
	}
}
#end
