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
	public var displayExpr : Expr;
	
	var context : DciContext;

	public function new(context : DciContext) {
		if (context == null) throw "context cannot be null.";		
		this.context = context;
	}

	function displayRole() : DciRole {
		function testEDisplay(e : Expr) : Bool {
			var output = false;
			function iterateForEDisplay(e : Expr) switch e.expr {
				case EDisplay(e2, _): 
					displayExpr = e2;
					output = true;
				case _:	e.iter(iterateForEDisplay);
			}
			iterateForEDisplay(e);
			return output;
		}	
		
		for (role in context.roles) for (rm in role.roleMethods) {
			if (testEDisplay(rm.method.expr)) return role;
		}
		
		return null;
	}
	
	// Return the function type, try to type it if it doesn't exist, or return Void as default.
	function functionType(func : Function) : ComplexType {
		var void = TPath( { sub: null, params: null, pack: [], name: "Void" } );
		
		return if (func.ret != null) {
			func.ret;
		} else if (func.expr == null) {
			void;
		} else try {
			Context.toComplexType(Context.typeof(func.expr));
		} catch (e : Dynamic) {
			void;
		}
	}

	public function fieldKindForRole(currentRole : DciRole) : FieldType {
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
		
		// If in the current role, merge the contract and rolemethods.
		if (currentRole == displayRole()) fields = fields.concat(currentRole.contract);
		
		var newType = defineRoleMethodType(currentRole, fields);
		if (displayExpr != null) displayExpr.expr = ECheckType(macro null, newType);
		
		return FVar(newType);
	}

	function defineRoleMethodType(role : DciRole, fields : Array<Field>) : ComplexType {
		var pack = ['dci'].concat(context.cls.pack).concat([context.name.toLowerCase()]);
		
		Context.defineType({
			pos: role.field.pos,
			params: null,
			pack: pack,
			name: role.name,
			meta: null,
			kind: TDStructure,
			isExtern: false,
			fields: fields
		});
		
		return TPath({ sub: null, params: null, pack: pack, name: role.name });
	}
}
#end
