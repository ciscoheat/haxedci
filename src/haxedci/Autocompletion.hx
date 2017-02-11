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
	var currentRole : Null<DciRole>;

	public function new(context : DciContext, currentRole : DciRole) {
		if (context == null) throw "context cannot be null.";
		this.context = context;
		this.currentRole = currentRole;
	}
	
	// e is the Expr inside EDisplay
	public function replaceDisplay(e : Expr, isCall : Bool) {
		switch e.expr {
			case EConst(CIdent(s)):
				
			case _:
		}
		/*
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
		*/
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
