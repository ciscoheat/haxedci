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
	public static var rmSignatures : Map<String, Array<Field>>;
	public static var rmSignaturesMtime : Float = 0;
	
	@macro public static function context() : Array<Field>
	{
		// Since the autocompletion cannot resolve all RoleMethods for a Role
		// unless inside the very last one, save signatures here for usage in
		// display mode.
		
		var file : String;
		var signatures = Context.definedValue("dci-signatures");
		
		if(signatures == null)
			file = Context.resolvePath('') + 'dci-signatures.bin';
		else if (signatures.indexOf('/') >= 0 || signatures.indexOf('\\') >= 0)
			file = signatures;
		else
			file = Context.resolvePath('') + signatures;
		
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
					//Dci.fileTrace("Unserializing rmSignatures: " + rmSignatures.array().length);
				} catch (e : Dynamic) {}
			} else {
				#if debug
				if (signatures != "") Context.onAfterGenerate(function() {
					// Write the RoleMethod signatures to a file so autocompletion can use it.
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
					File.saveContent(file, ser.toString());
					rmSignaturesMtime = FileSystem.stat(file).mtime.getTime();
					//Dci.fileTrace("Compiled rmSignatures: " + rmSignatures.array().length);
				});
				#end
			}
		} 
		#if debug
		else if (signatures != "" && Context.defined("display")) {
			if (rmSignaturesMtime < FileSystem.stat(file).mtime.getTime()) {
				//Dci.fileTrace("rmSignatures changed, renewing.");
				rmSignatures = null;
				return context();
			} else {
				//Dci.fileTrace("Reused rmSignatures: " + rmSignatures.array().length);
			}
		}
		#end
		
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

	public function addRoleMethods() : Array<Field>
	{
		var outputFields = [];
		
		//trace("======== Context: " + Context.getLocalClass());

		for (field in fields) {
			var role = roles.get(field.name);
			
			if (role != null)
				role.addFields(outputFields);
			else
				outputFields.push(field);
		}		

		// No more work to do in display mode.
		if (Context.defined("display")) return outputFields;

		for (field in outputFields) {
			new RoleMethodReplacer(roleMethodAssociations.get(field), this).replace(field);
		}
		
		for (role in roles) if (role.bound == null) {
			Context.warning("Role " + role.name + " isn't bound in this Context.", role.field.pos);
		}			
		
		return outputFields;
	}
}
