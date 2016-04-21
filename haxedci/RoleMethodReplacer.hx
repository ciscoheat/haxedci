package haxedci;
import haxedci.DciContext.DciRole;
import haxedci.DciContext.DciRoleMethod;

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

	var context : DciContext;
	var roles = new Map<String, DciRole>();
	var roleNames = ['self'];
	var roleMethodNames = new Map<String, Array<String>>();

	public function new(context : DciContext) {
		if (context == null) throw "context cannot be null.";
		
		this.context = context;
		
		for (role in context.roles) {
			roles.set(role.name, role);
			roleNames.push(role.name);
			roleMethodNames.set(role.name, [for (rm in role.roleMethods) rm.name]);
		}
	}
	
	public function replaceAll() {
		for (role in roles) replaceRole(role);
		for (field in context.fields) replaceField(field);
		
		trace("=== Fields rewritten for Context ==="); for (role in roles) for(rm in role.roleMethods) trace(rm.method.expr.toString());
	}

	function replaceRole(role : DciRole) {
		for (roleMethod in role.roleMethods) {
			replaceInExpr(roleMethod.method.expr, Option.Some(role), Option.Some(roleMethod.method));
		}		
	}

	function replaceField(field : Field) {
		switch(field.kind) {
			case FVar(_, e): if(e != null) replaceInExpr(e, Option.None, Option.None);
			case FFun(f): if(f.expr != null) replaceInExpr(f.expr, Option.None, Option.Some(f));
			case FProp(_, _, _, e): if(e != null) replaceInExpr(e, Option.None, Option.None);
		}
	}

	function replaceInExpr(e : Expr, currentRole : Option<DciRole>, currentFunction : Option<Function>) {
		var hasRole = !currentRole.equals(Option.None);
		
		/*
		function roleAliasTest(e2 : Expr) {
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
		*/
		
		switch(e.expr) {
			case EFunction(_, f) if(f.expr != null): 
				replaceInExpr(f.expr, currentRole, Some(f)); return;
			case EConst(CIdent(name)): 
				//if(hasRole) testIdentifiersInRoleMethods(name, e);
			case EField(e2, name): 
				//if(hasRole) testIdentifiersInRoleMethods(name, e2);
				if(replaceIdentifiers(e, currentRole)) return;
			case EBinop(OpAssign, e1, e2): 
				if (!setRoleBindPos(e1, currentRole, currentFunction)) {
					// Role wasn't bound, so test if something is being assigned to it. That's not allowed.
					//roleAliasTest(e2);
				}
			case EVars(vars):
				//for (v in vars) roleAliasTest(v.expr);
			case _:
		}

		e.iter(replaceInExpr.bind(_, currentRole, currentFunction));
	}

	/*
	function testIdentifiersInRoleMethods(name : String, e : Expr) {
		if (name == "this") Context.error('"this" keyword is not allowed in RoleMethods, use "self" or reference the Role directly instead.', e.pos);
		//if (!roleNames.has(name)) Context.error("RoleMethods can only reference its own or another Role.", e.pos);
	}
	*/

	// Returns true if a Role was successfully bound in the Expr.
	function setRoleBindPos(e : Expr, currentRole : Option<DciRole>, currentFunction : Option<Function>) : Bool {
		var fieldArray = extractIdentifier(e, currentRole);
		if (fieldArray == null) return false;
		if (fieldArray[0] == "this") fieldArray.shift();
		if (fieldArray.length != 1)	return false;
		
		var boundRole = roles.get(fieldArray[0]);
		if (boundRole == null) return false;

		// Set where the Role was bound in the Context.
		boundRole.bound = e.pos;

		switch(currentFunction) {
			case None: 
				Context.error('Role must be bound in a Context method!', e.pos);
				
			case Some(f):
				if (roleBindFunction == null) 
					roleBindFunction = f;
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
		/*
		switch(e.expr) {
			case EConst(CIdent(_)): e.expr = EConst(CIdent('__' + boundRole.name));
			case EField({expr: EConst(CIdent('this')), pos: _}, _): e.expr = EConst(CIdent('__' + boundRole.name));
			case _: Context.error("Non-obvious Role binding - Use a simpler assigment like 'this.role = object'", e.pos);
		}
		*/
		
		return true;
	}
	
	/**
	 * Returns an array of identifiers from the current expression,
	 * or null if the expression isn't an EField or EConst.
	 */
	function extractIdentifier(e : Expr, currentRole : Option<DciRole>) : Null<Array<String>> {
		return switch(e.expr) {
			case EField(e2, field): e.toString().split(".");
			case EConst(CIdent(s)): [s];
			case _:	return null;
		}
	}

	/**
	 * Given that console is a Role, rewriting 
	 * [console, cursor, pos] to [console__cursor, pos]
	 */
	function replaceIdentifiers(e : Expr, currentRoleOption : Option<DciRole>) : Bool {
		var fieldArray = extractIdentifier(e, currentRoleOption);
		var currentRole : DciRole = switch currentRoleOption { 
			case Option.None: null;
			case Option.Some(role): role;
		}
		
		switch fieldArray[0] {
			case "this" if (currentRole != null):
				Context.error('"this" keyword is not allowed in RoleMethods, use "self" or reference the Role directly instead.', e.pos);
				
			case "self" if (currentRole != null):
				fieldArray[0] = currentRole.name;
				
			case _:
		}
		
		var potentialRole = fieldArray[0];
		
		// Test if the field refers to a RoleMethod in the current Role, then prepend the current role.
		if (fieldArray.length == 1 && currentRole.name != "") {
			if(roleMethodNames.get(currentRole.name).has(potentialRole) || currentRole.contract.find(function(f) return f.name == potentialRole) != null)
				fieldArray.unshift(currentRole.name);
		}

		// Rewrite only if a RoleMethod is refered
		var potentialRoleMethod = fieldArray[1];
		
		if (roles.exists(potentialRole) && roleMethodNames.get(potentialRole).has(potentialRoleMethod)) {
			// Concatename the first and second fields.
			fieldArray[1] = potentialRole + "__" + potentialRoleMethod;
			fieldArray.shift();
		}

		trace(fieldArray);
		
		e.expr = (macro $p{fieldArray}).expr;
		return true;
	}	
}
#end
