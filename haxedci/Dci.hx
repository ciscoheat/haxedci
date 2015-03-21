package haxedci;

import haxe.ds.Option;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.Serializer;
import haxe.Unserializer;
import sys.FileStat;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
import haxedci.Role.RoleMethod;

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

	//////////////////////////////////////////////////
	
	/**
	 * System-wide role methods, to prevent collisions.
	 */
	static var roleMethods : Map<String, RoleMethod> = new Map<String, RoleMethod>();

	public var roles(default, null) : Map<Field, Null<Role>>;
	public var name(default, null) : String;

	public function new()
	{
		var cls = Context.getLocalClass().get();		
		name = cls.pack.toDotPath(cls.name);

		roles = new Map<Field, Null<Role>>();

		for (f in Context.getBuildFields())
			roles.set(f, Role.isRoleField(f) ? new Role(f) : null);
	}

	public function addRoleMethods() : Array<Field>
	{
		var outputFields = [];
		
		for (field in roles.keys()) {
			var role = roles.get(field);
			
			if (role != null) {
				role.addFields(outputFields);
			}
			else
				outputFields.push(field);
		}		

		var replacer = new RoleMethodReplacer(this);

		for (field in outputFields) {
			var role = roles.get(field);
			replacer.replace(field, role == null ? Option.None : Option.Some(role));
		}

		// No more work to do in display mode.
		if (Context.defined("display")) return outputFields;
		
		// After all replacement is done, test if all roles are bound.
		for (role in roles) if (role != null && role.bound == null) {
			Context.warning("Role " + role.name + " isn't bound in this Context.", role.field.pos);
		}			
		
		return outputFields;
	}
}
