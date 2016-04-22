package haxedci;

#if macro
import haxe.macro.Format;
import haxedci.DciContext;
import haxedci.DciContext.DciRole;
import haxedci.DciContext.DciRoleMethod;

import haxe.ds.Option;
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;

/**
 * Tests if roles are bound in the same function,
 * and replaces RoleMethod calls with its mangled representation.
 * i.e. console.cursor.pos => console__cursor.pos
 */
class Autocompletion
{
	var context : DciContext;

	public function new(context : DciContext) {
		if (context == null) throw "context cannot be null.";		
		this.context = context;
	}

	public function autocomplete() : Field {
		var output : Field;
		
		for (role in context.roles) for (rm in role.roleMethods) {
			output = testEDisplay(rm.method.expr, role);
			if (output != null) return output;
		}
		
		for (f in context.fields) switch f.kind {
			case FFun(f): 
				output = testEDisplay(f.expr, null);
				if (output != null) return output;
			case _:
		}
		
		return null;
	}

	function showMethodsFor(e : Expr, roleName : String) : Field {
		var role = context.roles.find(function(r) return r.name == roleName);
		if (role == null) return null;

		e.expr = EConst(CIdent("__autocompletion"));
		
		return {
			pos: e.pos,
			name: "__autocompletion",
			meta: null,
			kind: role.field.kind,
			doc: null,
			access: [APrivate]
		};
	}
	
	function testEDisplay(e : Expr, currentRole : DciRole) : Field {
		if (e == null) return null;
		
		var output = null;
		function displayCorrectMethods(e : Expr) {
			switch e.expr {
				case EDisplay(e2, isCall): 
					switch e2.expr {
						case EConst(CIdent(s)) | EField( { expr: EConst(CIdent("this")), pos: _ }, s):
							if (s == "self") s = currentRole.name;
							output = showMethodsFor(e2, s);
						case _:
					}					
				case _:
			}
			
			if (output != null) return;
			e.iter(displayCorrectMethods);
		}
		
		displayCorrectMethods(e);
		return output;
	}	
}
#end
