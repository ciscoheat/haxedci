package haxedci;

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
using Lambda;
using haxe.macro.MacroStringTools;

class Dci
{
	// "Context-Role" => Field
	public static var rmSignatures : Map<String, Array<Field>>;
	public static var rmSignaturesMtime : Float = 0;
	
	@macro public static function context() : Array<Field>
	{
		var file = Context.resolvePath('') + 'haxedci-signatures.bin';
		
		if (rmSignatures == null) {
			rmSignatures = new Map<String, Array<Field>>();
			if (Context.defined("display")) {
				try {
					var un = new Unserializer(File.getContent(file));
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
					rmSignaturesMtime = FileSystem.stat(file).mtime.getTime();
					Dci.fileTrace("Unserializing rmSignatures: " + rmSignatures.array().length);
				} catch (e : Dynamic) {}
			} else {
				Context.onAfterGenerate(function() {
					// Cannot serialize pos automatically.
					var ser = new Serializer();
					ser.serialize(rmSignatures.array().length);
					for (key in rmSignatures.keys()) {
						ser.serialize(key);
						ser.serialize(rmSignatures.get(key).length);
						for (field in rmSignatures.get(key)) {
							var p = Context.getPosInfos(field.pos);
							field.pos = null;
							ser.serialize(field);
							ser.serialize(p);
						}
					}
					File.saveContent(file, ser.toString());
					rmSignaturesMtime = FileSystem.stat(file).mtime.getTime();
					Dci.fileTrace(FileSystem.stat(file).mtime + " compiled rmSignatures: " + rmSignatures.array().length);
				});
			}
		} else if (Context.defined("display")) {
			if (rmSignaturesMtime < FileSystem.stat(file).mtime.getTime()) {
				Dci.fileTrace("rmSignatures changed, renewing.");
				rmSignatures = null;
				return context();
			} else {
				Dci.fileTrace("Reused rmSignatures: " + rmSignatures.array().length);
			}
		}
		
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
	
	public var name(default, null) : String;

	public function new()
	{
		var cls = Context.getLocalClass().get();
		
		name = cls.pack.toDotPath(cls.name);
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
			for (role in roles) {
				if (role.bound == null)
					Context.warning("Role " + role.name + " isn't bound in this Context.", role.field.pos);
				
				var cacheKey = this.name + '-' + role.name;
				
				rmSignatures.set(cacheKey, []);
				for (rm in role.roleMethods)
					rmSignatures.get(cacheKey).push(rm.signature);
			}			
		}
		
		return outputFields;
	}
}
