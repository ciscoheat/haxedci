package haxedci;

import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;

class RoleMethod
{
	public static var roleAccessor = "self";

	public static function mangledFieldName(roleName : String, roleMethod : String)	{
		return roleName + "__" + roleMethod;
	}

	public var name(get, null) : String;
	function get_name() return signature.name;
	
	public var role : Role;
	public var method : Function;
	public var field : Field;
	public var signature : Field;
	
	function returnSelf(pos : Position) return {expr: EReturn({expr: EConst(CIdent(roleAccessor)), pos: pos}), pos: pos};

	public function new(role : Role, name : String, method : Function) {
		this.role = role;
		this.method = method;

		this.signature = {
			kind: FFun({
				ret: method.ret,
				params: method.params,
				expr: null,
				args: method.args
			}),
			name: name,
			access: [],
			pos: method.expr.pos,
			meta: [],
			doc: null			
		};

		this.field = {
			pos: method.expr.pos,
			name: mangledFieldName(role.name, name),
			meta: [{ pos: method.expr.pos, params: [], name: ":noCompletion" }],
			kind: FFun(method),
			doc: null,
			access: [APrivate]
		};
		
		// RoleMethods returns self as default if not specified otherwise.
		// A compilation warning can be defined to warn for that.
		if (method.ret == null) {
			if(Context.defined("dci-signatures-warnings"))
				Context.warning("RoleMethod without explicit return value", method.expr.pos);

			// Set type to Role type
			method.ret = role.type;

			// Add return to block, or create a block with return statement
			if (method.expr == null)
				method.expr = returnSelf(field.pos);
			else {
				switch method.expr.expr {
					case EBlock(exprs):
						exprs.push(returnSelf(method.expr.pos));
					case _:
						method.expr = {
							expr: EBlock([method.expr, returnSelf(method.expr.pos)]), 
							pos: method.expr.pos
						};
				}
			}

			// Replace all empty return statements with return self
			method.expr = injectReturnSelf(method.expr);
		}
	}
	
	function injectReturnSelf(e : Expr) : Expr {
		return switch e.expr {
			case EReturn(e2) if (e2 == null): returnSelf(e.pos);
			case EFunction(_, _): e;
			case _: e.map(injectReturnSelf);
		}
	}
}
