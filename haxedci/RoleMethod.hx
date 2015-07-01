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
			//method.ret = TPath({sub: null, params: null, pack: [], name: "Void"});
			method.ret = role.type;
			
			// Inject "return self" at return statements
			var returnSelf = (macro return $v{roleAccessor}).expr;
			
			if (method.expr == null) {
				method.expr = {
					expr: returnSelf,
					pos: method.expr.pos
				}
			}
			else {
				method.expr.expr = switch method.expr.expr {
					case EBlock(exprs):
						exprs.push({expr: returnSelf, pos: method.expr.pos});
						method.expr.expr;
					case _:
						EBlock([method.expr, {expr: returnSelf, pos: method.expr.pos}]);
				}
	
				injectReturnSelf(method.expr);
			}
		}
	}
	
	function injectReturnSelf(e : Expr) {
		return switch e.expr {
			case EReturn(e) if (e == null): macro return $v{roleAccessor};
			case _: e.map(injectReturnSelf);
		}
	}
}
