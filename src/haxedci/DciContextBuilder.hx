package haxedci;

#if macro
import haxe.ds.Option;
import haxe.macro.Compiler;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.Serializer;
import haxe.Unserializer;
import haxedci.DciContext.DciRole;
import haxedci.DciContext.DciRoleMethod;

using Lambda;
using StringTools;
using haxe.macro.ExprTools;
using haxe.macro.MacroStringTools;

class DciContextBuilder
{
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

	//////////////////////////////////////////////////
	
	public static function build() : Array<Field> {
		var contextFields = Context.getBuildFields();

		// Create the Context
		var context = new DciContext(
			contextFields.filter(function(f) return !isRoleField(f)),
			contextFields.filter(isRoleField).map(fieldToRole)
		);

		function showMethodsFor(e : Expr, roleName : String) {
			var role = context.roles.find(function(r) return r.name == roleName);
			if (role != null) fileTrace(role.name);
		}
		
		function displayCorrectMethods(e : Expr) {
			switch e.expr {
				case EDisplay(e2, isCall): 
					switch e2.expr {
						case EConst(CIdent(s)) | EField({expr: EConst(CIdent("this")), pos: _}, s):
							showMethodsFor(e2, s);
						case _:
					}					
				case _:
			}
			
			e.iter(displayCorrectMethods);
		}

		if (Context.defined("display")) {
			for (f in context.fields) switch f.kind {
				case FFun(f): displayCorrectMethods(f.expr);
				case _:
			}
		}

		// Rewrite RoleMethod calls (destination.deposit -> destination__desposit)
		new RoleMethodReplacer(context).replaceAll();
		
		var outputFields = context.fields.concat(context.roles.map(function(role) return role.field));
		
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
		
		// After all replacement is done, test if all roles are bound.
		for (r in context.roles) if(r.bound == null) {
			Context.warning("Role " + r.name + " isn't bound in this Context.", r.field.pos);
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

	// Return the function type, try to type it if it doesn't exist, or return Void as default.
	static function functionType(func : Function) : ComplexType {
		var void = TPath( { sub: null, params: null, pack: [], name: "Void" } );
		
		return if (func.ret != null) {
			func.ret;
		} else if (func.expr == null) {
			void;
		} else try {
			Context.toComplexType(Context.typeof(func.expr));
		} catch (e : Dynamic) {
			void;
		}
	}
	
	static function fieldToRole(field : Field) : DciRole {
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
				
				new DciRole(field, roleMethods);
				
			case _: 
				Context.error("Only var fields can be a Role.", field.pos);
		}
	}
}
#end
