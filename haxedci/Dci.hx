package haxedci;

import haxe.macro.Expr;
import haxe.macro.Context;
import sys.io.File;
import sys.io.FileOutput;
using Lambda;

class Dci
{
	@macro public static function context() : Array<Field>
	{
		return new Dci().execute();
	}

	public static function fileTrace(o : Dynamic, file = "e:\\temp\\fileTrace.txt")
	{
		var f : FileOutput;
		try f = File.append(file, false)
		catch (e : Dynamic) f = File.write(file, false);
		f.writeString(Std.string(o) + "\n");
		f.close();
	}
	
	/**
	 * Class field name => Role
	 */
	public var roles(default, null) : Map<String, Role>;
	
	/**
	 * RoleMethod field => Role
	 */
	public var roleMethodAssociations(default, null) : Map<Field, Role>;

	/**
	 * Last role bind function, to test role binding errors.
	 */
	public var roleBindMethod : Function;

	/**
	 * Last role bind position, in case of a role binding error.
	 */
	public var lastRoleBindPos : Position;
	
	var fields : Array<Field>;

	public function new()
	{
		fields = Context.getBuildFields();
		roles = new Map<String, Role>();
		roleMethodAssociations = new Map<Field, Role>();
		
		for (f in fields.filter(Role.isRoleField))
			roles.set(f.name, new Role(f, this));
	}

	public function execute() : Array<Field>
	{
		var outputFields = [];

		//trace("======== Context: " + Context.getLocalClass());

		// Loop through fields again to avoid putting them in incorrect order.
		for (field in fields) {
			var role = roles.get(field.name);
			if (role != null) {
				role.addFields(outputFields);
			}
			else {
				outputFields.push(field);
			}
		}
		

		for (field in outputFields) {
			var role = roleMethodAssociations.get(field);
			//trace(field.name + " has role " + (role == null ? '<no role>' : role.name));
			new RoleMethodReplacer(field, roleMethodAssociations.get(field), this).replace();
		}

		if (!Context.defined("display")) {
			// Test if all roles were bound.
			for (role in roles) if (role.bound == null)
				Context.warning("Role " + role.name + " isn't bound in this Context.", role.field.pos);			
		}
		
		return outputFields;
	}
}
