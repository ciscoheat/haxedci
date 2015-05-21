package haxedci;

#if macro
import haxe.ds.Option;
import sys.io.File;
import sys.io.FileOutput;
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;

/**
 * Tests if roles are bound in the same function,
 * and replaces RoleMethod calls with its mangled representation.
 * i.e. console.cursor.pos => console__cursor.pos
 */
class RoleMethodReplacer
{
	/**
	 * Last role bind function, to test role binding errors.
	 */
	var roleBindFunction : Function;

	var roles : Map<String, Role>;

	public function new(context : Dci) {
		if (context == null) throw "context cannot be null.";

		this.roles = new Map<String, Role>();

		for(role in context.roles) roles.set(role.name, role);
	}

	public function replaceRoleMethod(roleMethod : RoleMethod) {
		replace(roleMethod.field, Option.Some(roleMethod.role));
	}

	public function replaceField(field : Field) {
		replace(field, Option.None);
	}

	function replace(field : Field, currentRole : Option<Role>) {
		switch(field.kind) {
			case FVar(_, e): if(e != null) e.iter(replaceInExpr.bind(_, currentRole, Option.None));
			case FFun(f): if(f.expr != null) f.expr.iter(replaceInExpr.bind(_, currentRole, Option.Some(f)));
			case FProp(_, _, _, e): if(e != null) e.iter(replaceInExpr.bind(_, currentRole, Option.None));
		}			
	}
	
	function replaceInExpr(e : Expr, currentRole : Option<Role>, currentFunction : Option<Function>) {
		var hasRole = !currentRole.equals(Option.None);
		
		var roleAliasTest = null;
		roleAliasTest = function(e2 : Expr) {
			if (e2 == null) return;
			switch(e2.expr) {
				case EParenthesis(e3): roleAliasTest(e3);
				case EConst(CIdent(s)):
					for (roleName in roles.keys()) if (roleName == s)
						Context.error("Aliasing a Role isn't allowed, access a Role only through its given name.", e.pos);
				case EField({expr: EConst(CIdent('this')), pos: _}, field):
					for (roleName in roles.keys()) if (roleName == field)
						Context.error("Aliasing a Role isn't allowed, access a Role only through its given name.", e.pos);
				case EBinop(OpAssign, e1, _):
					roleAliasTest(e1);
				case _:
			}
		}
		
		switch(e.expr) {
			case EFunction(_, f) if(f.expr != null): 
				replaceInExpr(f.expr, currentRole, Some(f)); return;
			case EConst(CIdent(name)): 
				if(hasRole) testIdentifiersInRoleMethods(name, e);
			case EField(e2, name): 
				if(hasRole) testIdentifiersInRoleMethods(name, e2);
				if(replaceIdentifiers(e, currentRole)) return;
			case EBinop(OpAssign, e1, e2): 
				if (!setRoleBindPos(e1, currentRole, currentFunction)) {
					// Role wasn't bound, so test if something is being assigned to it. That's not allowed.
					roleAliasTest(e2);
				}
			case EVars(vars):
				for (v in vars) 
					roleAliasTest(v.expr);
			case _:
		}

		e.iter(replaceInExpr.bind(_, currentRole, currentFunction));
	}

	function testIdentifiersInRoleMethods(name : String, e : Expr) {
		if(name == "this") Context.error('"this" keyword is not allowed in RoleMethods, reference the field directly instead.', e.pos);
	}

	// Returns true if a Role was successfully bound in the Expr.
	function setRoleBindPos(e : Expr, currentRole : Option<Role>, currentFunction : Option<Function>) : Bool {
		var fieldArray = extractIdentifier(e, currentRole);
		if (fieldArray == null) return false;
		if (fieldArray[0] == "this") fieldArray.shift();
		if (fieldArray.length != 1)	return false;
		
		var boundRole = roles.get(fieldArray[0]);
		if (boundRole == null) return false;

		// Set where the Role was bound in the Context.
		boundRole.bound = e.pos;

		switch(currentFunction) {
			case None: Context.error('Role must be bound in a Context method!', e.pos);
			case Some(f):
				if (roleBindFunction == null) {
					roleBindFunction = f;
				}
				else if (roleBindFunction != f) {
					Context.warning(
						'All Roles in a Context must be assigned in the same function.', 
						roleBindFunction.expr.pos
					);
					Context.error(
						'All Roles in a Context must be assigned in the same function.', 
						e.pos
					);
				}
		}

		// Rewrite the Role assignment to the hidden __role variable.
		switch(e.expr) {
			case EConst(CIdent(_)): e.expr = EConst(CIdent('__' + boundRole.name));
			case EField({expr: EConst(CIdent('this')), pos: _}, _): e.expr = EConst(CIdent('__' + boundRole.name));
			case _: Context.error("Non-obvious Role binding - Use a simpler assigment.", e.pos);
		}		
		
		return true;
	}
	
	/**
	 * Returns an array of identifiers from the current expression,
	 * or null if the expression isn't an EField or EConst.
	 */
	function extractIdentifier(e : Expr, currentRole : Option<Role>) : Null<Array<String>> {
		var fields = [];
		while (true) {
			switch(e.expr) {
				case EField(e2, field):
					var replace = switch(currentRole) {
						case None: field;
						case Some(r): (field == RoleMethod.roleAccessor) ? r.name : field;
					}
					fields.unshift(replace);
					e = e2;

				case EConst(CIdent(s)):
					var replace = switch(currentRole)	{
						case None: s;
						case Some(r): (s == RoleMethod.roleAccessor) ? r.name : s;
					}
					fields.unshift(replace);
					return fields;

				case _:	
					return null;
			}
		}
	}

	/**
	 * Given that console is a Role, rewriting 
	 * [console, cursor, pos] to [console__cursor, pos]
	 */
	function replaceIdentifiers(e : Expr, currentRole : Option<Role>) {
		var fieldArray = extractIdentifier(e, currentRole);
		if (fieldArray == null) return false;
		
		//trace(fieldArray);

		var newArray = [];
		var skip = false;
		var length = fieldArray.length;

		for (i in 0...length) {
			if (skip) {
				skip = false;
				continue;
			}
			
			var field = fieldArray[i];
			if (i > length - 2) {
				newArray.push(field);
			} else {
				// Test if a Role is matching the field.
				var matchingRole = roles.get(field);

				if (matchingRole != null && matchingRole.roleMethods.exists(fieldArray[i + 1])) {
					newArray.push(RoleMethod.mangledFieldName(fieldArray[i], fieldArray[i+1]));
					skip = true; // Skip next field since it's now a part of the Role method call.
				} else {
					newArray.push(field);
				}
			}
		}
		
		if (fieldArray.length != newArray.length) {
			e.expr = (macro $p{newArray}).expr;
			return true;
		}
		
		return false;
	}	
}
#end
