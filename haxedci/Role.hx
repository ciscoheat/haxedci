package haxedci;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;

class Role
{
	public static var CONTEXT = "context";
	public static var SELF = "self";

	public static function roleMethodFieldName(roleName : String, roleMethod : String)
	{
		return roleName + "__" + roleMethod;
	}

	public static function isRoleField(field : Field) {
		if (!field.meta.exists(function(m) return m.name == "role")) return false;
		var error = function() {
			Context.error("@role can only be used on non-static var fields.", field.pos);
			return false;
		}
		
		switch(field.kind) {
			case FVar(_, _): 
				return field.access.has(AStatic) ? error() : true;
			case _:
				return error();
		}
	}
	
	public function new(field : Field, context : Dci) {
		if (field == null) throw "Null field.";
		if (context == null) throw "Null context.";

		this.context = context;
		this.field = field;
		this.bound = null;
		this.roleMethods = get_roleMethods();

		// Add "self" and "context" to roleMethods.
		for (rm in roleMethods)
			roleMethods_addSelf(rm);

		// Remove expr from field, not needed anymore when roleMethods are extracted
		// And for convenience, because now it can simply be added in addFields()
		switch(field.kind) {
			case FVar(t, e):
				field.kind = FVar(t, null);
			case _:
				Context.error("Only var fields can be a Role.", field.pos);
		}
	}
	
	public function addFields(fields : Array<Field>) {
		//new RoleObjectContractTypeMerger(field, this).merge(fields);
		
		if(!Context.defined("display"))
			fields.push(field);
		else
			new RoleObjectContractTypeMerger(field, this).merge(fields);

		// Add the RoleMethods
		for (rmName in roleMethods.keys()) {
			var rm = roleMethods.get(rmName);
			var field = {
				pos: rm.expr.pos,
				name: roleMethodFieldName(this.name, rmName),
				meta: [{ pos: rm.expr.pos, params: [], name: ":noCompletion" }],
				kind: FFun(rm),
				doc: null,
				access: [APrivate]
			};
			
			context.roleMethodAssociations.set(field, this);
			fields.push(field);
		}
	}

	var context : Dci;

	public var field(default, null) : Field;
	public var bound(default, default) : Position;

	public var name(get, null) : String;
	function get_name() return field.name;

	/**
	 * Method name => Function
	 */
	public var roleMethods(default, null) : Map<String, Function>;
	function get_roleMethods() {
		var output = new Map<String, Function>();
		switch(field.kind) {
			case FVar(t, e): 
				if (t == null)
					Context.error("A Role var must have a Type as RoleInterface.", field.pos);
				if(e != null) switch e.expr {
					case EBlock(exprs): for(e in exprs) switch e.expr {
						case EFunction(name, f):
							if (name == null) Context.error("A RoleMethod must have a name.", e.pos);
							output.set(name, f);
						case _:
							Context.error("A Role can only contain RoleMethods.", e.pos);
					}
					case _: 
						Context.error("A Role can only be assigned a block of RoleMethods.", e.pos);
				}
			case _:
				Context.error("Only var fields can be a Role.", field.pos);
		};
		return output;
	}

	function roleMethods_addSelf(f : Function)
	{
		var roleName = this.name;
		switch(f.expr.expr)
		{
			case EBlock(exprs):
				exprs.unshift(macro var $SELF = this.$roleName);
				exprs.unshift(macro var $CONTEXT = this);
			case _:
				f.expr = {expr: EBlock([f.expr]), pos: f.expr.pos};
				roleMethods_addSelf(f);
		}
	}
}
#end
