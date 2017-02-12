package haxedci;

import haxe.macro.Format;
import haxedci.DciContext;
import haxedci.DciContext.DciRole;
import haxedci.DciContext.DciRoleMethod;

import haxe.ds.Option;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.MacroStringTools;

using haxe.macro.ExprTools;
using Lambda;

class Autocompletion
{
	#if macro
	var context : DciContext;
	var currentRoleName : String;
	var currentRoleMethod : DciRoleMethod;
	var roles = new Map<String, DciRole>();

	public function new(context : DciContext, currentRole : Option<DciRole>, currentRoleMethod : Option<DciRoleMethod>) {
		if (context == null) throw "context cannot be null.";
		
		this.context = context;

		this.currentRoleName = switch currentRole {
			case None: null;
			case Some(role): role.name;
		};
		
		context.autocomplete = switch currentRoleMethod {
			case None: null;
			case Some(roleMethod): roleMethod;
		}
		
		for (role in context.roles)
			roles.set(role.name, role);
	}
	
	// e is the Expr inside EDisplay
	public function replaceDisplay(e : Expr, isCall : Bool) {		

		switch e.expr {
			case EConst(CIdent(roleName)) | EField({expr: EConst(CIdent("this")), pos: _}, roleName)
				if (roleName == "self" || roles.exists(roleName)): {
					if (roleName == "self") roleName = currentRoleName;
					
					var role = roles.get(roleName);
					// Transform the RoleMethods to Array<Field>
					var fields = [for (rm in role.roleMethods) {
						pos: rm.method.expr.pos,
						name: rm.name,
						meta: null,
						kind: FFun({
							ret: functionType(rm.method),
							params: rm.method.params,
							expr: null,
							args: rm.method.args
						}),
						doc: null,
						access: [APublic]// rm.isPublic ? [APublic] : [APrivate]
					}];

					// If we're inside the role that's autocompleted, add its contract fields to output.
					if (currentRoleName == role.name) {
						fields = fields.concat(role.contract);
					}
					else
						fields = fields.filter(
							function(f) return f.access != null && f.access.has(APublic)
						)
						.concat(role.contract.filter(
							function(f) return f.access != null && f.access.has(APublic))
						);
						
					e.expr = ECheckType(macro null, TAnonymous(fields));
				}
			case _:
		}
	}
	
	// Return the function type or Dynamic as default. This makes autocompletion work
	// even if the function has no explicit return type, or if the function is containing EDisplay.
	function functionType(func : Function) : ComplexType {
		return func.ret != null
			? func.ret
			: TPath( { sub: null, params: null, pack: [], name: "Dynamic" } );
	}	
	#end
	
	///////////////////////////////////////////////////////////////////////////
	
	// Debugging autocompletion is very tedious, so here's a helper method.
	public static function fileTrace(o : Dynamic, ?file : String)
	{
		file = Context.definedValue("filetrace");
		if (file == null) file = "e:\\temp\\filetrace.txt";
		
		var f = try sys.io.File.append(file, false)
		catch (e : Dynamic) sys.io.File.write(file, false);
		f.writeString(Std.string(o) + "\n");
		f.close();
	}	
}
