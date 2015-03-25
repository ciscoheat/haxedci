package haxedci;

import haxe.ds.Option;
import haxe.macro.Compiler;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.Serializer;
import haxe.Unserializer;
/*
import haxe.io.Bytes;
import haxe.io.Path;
import sys.FileStat;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
*/

using Lambda;
using StringTools;
using haxe.macro.MacroStringTools;

/**
 * A syntax-level DCI Context. This means that concepts like a Role
 * Aren't a true DCI Role, more like how a programmer that implements DCI
 * would think about a Role.
 */
class Dci
{
	// "Context-Role" => Field
	public static var rmSignatures : Map<String, Array<Field>> = new Map<String, Array<Field>>();
	
	@macro public static function context() : Array<Field>
	{
		// Since the autocompletion cannot resolve all RoleMethods for a Role
		// unless inside the very last one, save signatures here for usage in
		// display mode.
		
		/*
		var signatures = Context.defined("dci-signatures") || Context.defined("debug");

		if(signatures && !Context.defined("display")) {
			Context.onAfterGenerate(function() {
				var ser = new Serializer();
				ser.serialize(rmSignatures.array().length);
				for (key in rmSignatures.keys()) {
					ser.serialize(key);
					ser.serialize(rmSignatures.get(key).length);
					for (field in rmSignatures.get(key)) {
						// Cannot serialize pos automatically...
						var p = Context.getPosInfos(field.pos);
						field.pos = null;
						ser.serialize(field);
						ser.serialize(p);
					}
				}

				Context.addResource("dci-signatures", Bytes.ofString(ser.toString()));
				trace("Compiled rmSignatures: " + rmSignatures.array().length);
			});
		}		
		else if (rmSignatures == null && Context.defined("display")) {
			rmSignatures = new Map<String, Array<Field>>();
			try {
				var un = new Unserializer(haxe.Resource.getString("dci-signatures"));
				var i = un.unserialize();
				while (i-- > 0) {
					var fields = [];
					rmSignatures.set(un.unserialize(), fields);
					var i2 = un.unserialize();
					while (i2-- > 0) {
						fields.push(un.unserialize());
						fields[fields.length - 1].pos = Context.makePosition(un.unserialize());
					}
				}
				//Dci.fileTrace("Unserializing rmSignatures: " + rmSignatures.array().length);
			} catch (e : Dynamic) {}
		}
		*/
		
		return new Dci().addRoleMethods();
	}

	/**
	 * Debugging autocompletion is very tedious, so here's a helper method.
	 */
	 /*
	public static function fileTrace(o : Dynamic, ?file : String)
	{
		file = Context.definedValue("filetrace");
		if (file == null) file = "e:\\temp\\filetrace.txt";
		
		var f : FileOutput;
		try f = File.append(file, false)
		catch (e : Dynamic) f = File.write(file, false);
		f.writeString(Std.string(o) + "\n");
		f.close();
	}
	*/

	//////////////////////////////////////////////////
	
	/**
	 * System-wide role methods, to prevent collisions.
	 */
	static var allRoleMethods : Map<String, RoleMethod> = new Map<String, RoleMethod>();

	public var fields(default, null) : Array<Field>;

	public var roles(default, null) : Array<Role>;

	public var roleMethods(default, null) : Array<RoleMethod>;

	var name(default, null) : String;

	public function new()
	{
		var cls = Context.getLocalClass().get();
		name = cls.pack.toDotPath(cls.name);

		fields = Context.getBuildFields().filter(function(f) return !isRoleField(f));
		roles = Context.getBuildFields().filter(isRoleField).map(function(f) return new Role(f));
		roleMethods = [for(role in roles) for(rm in role.roleMethods) rm];
	}

	static function isRoleField(field : Field) {
		if (!field.meta.exists(function(m) return m.name == "role")) return false;
		var error = function() {
			Context.error("@role can only be used on non-static var fields.", field.pos);
			return false;
		}
		
		switch(field.kind) {
			case FVar(_, _): 
				return field.access.has(AStatic) ? error() : true;
			case _:
				return error();
		}
	}

	public function addRoleMethods() : Array<Field>
	{
		var replacer = new RoleMethodReplacer(this);

		//trace("=== Context: " + this.name);

		for(f in fields) {
			//trace("Adding field " + f.name);
			replacer.replaceField(f);
		}

		for (role in roles) {
			var roleAliasInjection = [
				(macro var port = $i{role.name}, self = port)
			];
			var roleField = role.field;			
			switch(roleField.kind) {
				case FVar(t, e):
					// Removing the RoleMethods from the Field definition so it can be used as a normal Field.
					roleField.kind = Context.defined("display") 
						? FVar(new RoleObjectContractTypeMerger(role).mergedType(), null)
						: FVar(t, null);
				case _:
					Context.error("Only var fields can be a Role.", roleField.pos);
			}
			
			//trace("Adding role: " + roleField.name);
			fields.push(roleField);

			// Add the RoleMethods
			for (roleMethod in role.roleMethods) {
				if(allRoleMethods.exists(roleMethod.name) && !Context.defined("dci-allow-name-collisions")) {
					var error = "RoleMethod name collision - cannot have same RoleMethod names in different Contexts.";
					Context.warning(error, roleMethod.field.pos);
					Context.error(error, allRoleMethods.get(roleMethod.name).field.pos);
				}

				replacer.replaceRoleMethod(roleMethod);
				//trace("Adding roleMethod: " + roleMethod.field.name);
				fields.push(roleMethod.field);

				// Add "port" to roleMethods
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

				#if debug
				if (roleMethod.method.ret == null && Context.defined("dci-signatures-warnings")) {
					Context.warning("RoleMethod without explicit return value", roleMethod.method.expr.pos);
				}
				#end
			}

			// Add to allRoleMethods for name collision testing.
			for(roleMethod in role.roleMethods) {
				allRoleMethods.set(roleMethod.name, roleMethod);
			}
		}

		// After all replacement is done, test if all roles are bound.
		if(!Context.defined("display")) {
			for (r in roles) if(r.bound == null)
				Context.warning("Role " + r.name + " isn't bound in this Context.", r.field.pos);
		}
		
		return fields;
	}
}
