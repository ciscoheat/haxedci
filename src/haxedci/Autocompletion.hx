package haxedci;

#if macro
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
	var context : DciContext;
	var currentRole : DciRole;

	public function new(context : DciContext, currentRole : DciRole) {
		if (context == null) throw "context cannot be null.";
		if (currentRole == null) throw "currentRole cannot be null.";
		this.context = context;
		this.currentRole = currentRole;
	}
	
	public function searchForDisplay(roleMethod : DciRoleMethod) : Bool {
		var e = findEDisplay(roleMethod.method.expr);
		if (e != null) switch(e.expr) {
			case EDisplay(e2, isCall):
				e2.expr = EConst(CString("test"));
				//fileTrace((isCall ? '[call] ' : '') + e2.toString());
				//fileTrace(e2.expr);
			case _:
		}
		return e != null;
	}
	
	public function fieldKindForRole(currentRole : DciRole) : FieldType {
		// Transform the RoleMethods to Array<Field>
		var fields = [for (rm in currentRole.roleMethods) {
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
			access: rm.isPublic ? [APublic] : [APrivate]
		}];

		// If we're inside the role that's autocompleted, add its contract fields to output.
		if (currentRole == currentDisplayRole())
			fields = fields.concat(currentRole.contract);
		else
			fields = fields.filter(function(f) return f.access != null && f.access.has(APublic)).concat(
				currentRole.contract.filter(function(f) return f.access != null && f.access.has(APublic)
			));
			
		//DciContextBuilder.fileTrace(context.name + '.' + currentRole.name + ': ' + fields.map(function(f) return f.name));
			
		return FVar(TAnonymous(fields));
	}
	
	// Return the function type or Dynamic as default. This makes autocompletion work
	// even if the function has no explicit return type, or if the function is containing EDisplay.
	function functionType(func : Function) : ComplexType {
		return func.ret != null
			? func.ret
			: TPath( { sub: null, params: null, pack: [], name: "Dynamic" } );
	}	

	function currentDisplayRole() : DciRole {
		for (role in context.roles) for (rm in role.roleMethods) {
			if (findEDisplay(rm.method.expr) != null) return role;
		}
		
		return null;
	}

	function findEDisplay(e : Expr) : Expr {
		var output : Expr = null;
		function iterForEDisplay(e : Expr) switch e.expr {
			case EDisplay(_, _): output = e;
			case _: e.iter(iterForEDisplay);
		}
		iterForEDisplay(e);
		return output;
	}
	
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
#end
