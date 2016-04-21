package haxedci;

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
using haxe.macro.MacroStringTools;

class DciContextBuilder
{
	// Debugging autocompletion is very tedious, so here's a helper method.
	/*
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
	*/

	//////////////////////////////////////////////////
	
	public static function build() : Array<Field> {
		//var cls = Context.getLocalClass().get();
		//name = cls.pack.toDotPath(cls.name);
		
		var contextFields = Context.getBuildFields();

		// Create the Context
		var context = new DciContext(
			contextFields.filter(function(f) return !isRoleField(f)),
			contextFields.filter(isRoleField).map(fieldToRole)
		);

		// Rewrite RoleMethod calls (destination.deposit -> destination__desposit)
		new RoleMethodReplacer(context).replaceAll();
		
		// Fix return types of contracts (try to type, or set to Void if not exists)
		// It must be done after rewriting RoleMethod calls, otherwise the compiler could fail
		// on "self" calls, for example.
		/*
		for (role in context.roles) for(contractField in role.contract) switch contractField.kind {
			case FFun(f): f.ret = functionType(f);
			case _:
		}
		*/
		
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
			trace("No function type, returning void");
			void;
		} else try {
			var type = Context.toComplexType(Context.typeof(func.expr));
			trace("Parsed type to " + type);
			type;
		} catch (e : Dynamic) {
			trace("RoleMethod typing error: " + e);
			trace(func);
			void;
		}
	}
	
	static function fieldToRole(field : Field) : DciRole {
		function incorrectTypeError() {
			Context.error("A Role must have an anonymous structure as its contract. See http://haxe.org/manual/types-anonymous-structure.html for syntax.", field.pos);
		}
		function basicTypeError(name) {
			Context.error(name + " is a basic type (Int, Bool, Float), only objects can play a Role in a Context. " + 
				"You can make it a normal field instead, or pass it as a parameter.", field.pos);
		}
		
		return switch field.kind {
			case FVar(t, e): 				
				if (t == null) incorrectTypeError();

				switch(t) {
					case TAnonymous(fields): // OK

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

	/*
	public function addRoleMethods() : Array<Field>
	{
		var roleAccessor = RoleMethod.roleAccessor;
		var replacer = new RoleMethodReplacer(this);

		for(f in fields) {
			//trace("Adding field " + f.name);
			replacer.replaceField(f);
		}

		for (role in roles) {
			var roleAliasInjection = [macro var $roleAccessor = $i{role.name}];
			var roleField = role.field;
			
			switch(roleField.kind) {
				case FVar(t, e):
					if(Context.defined("display"))
						roleField.kind = FVar(new RoleObjectContractTypeMerger(role, this).mergedType(), null);						
					else {
						// Add a getter to the role field to prevent reassignment of Roles.
						roleField.kind = FProp('get', 'never', t, null);
						fields.push({
							pos: roleField.pos,
							name: '__' + role.name,
							meta: [{ pos: roleField.pos, params: [], name: ":noCompletion" }],
							kind: FVar(t, null)
						});
						fields.push({
							pos: roleField.pos,
							name: 'get_' + role.name,
							meta: null,
							kind: FFun({
								ret: t,
								params: null,
								expr: macro return $i{'__' + role.name},
								args: []
							})
						});
					}
				case _:
					Context.error("Only var fields can be a Role.", roleField.pos);
			}
			
			//trace("Adding role: " + roleField.name);
			fields.push(roleField);

			// Add the RoleMethods
			for (roleMethod in role.roleMethods) {

				replacer.replaceRoleMethod(roleMethod);
				//trace("Adding roleMethod: " + roleMethod.field.name);
				fields.push(roleMethod.field);

				// Add "self" to roleMethods
				var method = roleMethod.method;

				switch(method.expr.expr)	{
					case EBlock(exprs): 
						for(expr in roleAliasInjection) exprs.unshift(expr);
					case _:
						method.expr = {
							expr: EBlock(roleAliasInjection.concat([method.expr])), 
							pos: method.expr.pos
						};
				}
			}
		}

		// After all replacement is done, test if all roles are bound.
		if(!Context.defined("display")) {
			for (r in roles) if(r.bound == null)
				Context.warning("Role " + r.name + " isn't bound in this Context.", r.field.pos);
		}
		
		return fields;
	}
	*/
}
