package haxedci;

import haxe.ds.Option;
import haxe.macro.Compiler;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.Serializer;
import haxe.Unserializer;

using Lambda;
using StringTools;
using haxe.macro.MacroStringTools;

class Dci
{
	@macro public static function context() : Array<Field> {
		return new Dci().addRoleMethods();
	}

	static function isRoleField(field : Field) {
		if (!field.meta.exists(function(m) return m.name == "role")) return false;
		
		var error = function() {
			Context.error("@role can only be used on non-static var fields.", field.pos);
			return false;
		}
		
		switch(field.kind) {
			case FVar(_, _): return field.access.has(AStatic) ? error() : true;
			case _: return error();
		}
	}

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
	
	public var fields(default, null) : Array<Field>;
	public var roles(default, null) : Array<Role>;
	public var roleMethods(default, null) : Array<RoleMethod>;

	public var name(default, null) : String;

	public function new()
	{
		var cls = Context.getLocalClass().get();
		name = cls.pack.toDotPath(cls.name);

		fields = Context.getBuildFields().filter(function(f) return !isRoleField(f));
		roles = Context.getBuildFields().filter(isRoleField).map(function(f) return new Role(f));
		roleMethods = [for(role in roles) for(rm in role.roleMethods) rm];
	}

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
				/*
				if(allRoleMethods.exists(roleMethod.name) && !Context.defined("dci-allow-name-collisions")) {
					var error = "RoleMethod name collision - cannot have same RoleMethod names in different Contexts.";
					Context.warning(error, roleMethod.field.pos);
					Context.error(error, allRoleMethods.get(roleMethod.name).field.pos);
				}
				*/

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

		// Finally add RoleMethods to allRoleMethods to test for collisions.
		/*
		for(role in roles) {
			for(roleMethod in role.roleMethods) {
				allRoleMethods.set(roleMethod.name, roleMethod);
			}
		}
		*/

		// After all replacement is done, test if all roles are bound.
		if(!Context.defined("display")) {
			for (r in roles) if(r.bound == null)
				Context.warning("Role " + r.name + " isn't bound in this Context.", r.field.pos);
		}
		
		return fields;
	}
}
