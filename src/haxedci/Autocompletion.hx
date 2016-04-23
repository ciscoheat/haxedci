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

	public function new(context : DciContext) {
		if (context == null) throw "context cannot be null.";		
		this.context = context;
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
			access: null
		}];

		// If we're inside the role that's autocompleted, add its contract fields to output.
		if (currentRole == currentDisplayRole())
			fields = fields.concat(currentRole.contract);
			
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
			if (hasEDisplay(rm.method.expr)) return role;
		}
		
		return null;
	}

	function hasEDisplay(e : Expr) : Bool {
		var status = false;
		function iterForEDisplay(e : Expr) switch e.expr {
			case EDisplay(_, _): status = true;
			case _: e.iter(iterForEDisplay);
		}
		iterForEDisplay(e);
		return status;
	}
}
#end
