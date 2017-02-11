package haxedci;

#if macro
import haxe.macro.Format;
import haxedci.DciContext;
import haxedci.DciContext.DciRole;
import haxedci.DciContext.DciRoleMethod;
import haxedci.Autocompletion.fileTrace;

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
class RoleMethodReplacer
{
	/**
	 * Last role bind function, to test role binding errors.
	 */
	var roleBindFunction : Function;

	var context : DciContext;
	var roles = new Map<String, DciRole>();

	public function new(context : DciContext) {
		this.context = context;
		
		for (role in context.roles)
			this.roles.set(role.name, role);
	}
	
	public function replaceAll() {
		for (role in roles) replaceRole(role);
		for (field in context.normalFields) {
			replaceField(field);
		}
		
		// After all replacement is done, test if all roles are bound.
		if (!Context.defined("display")) {
			for (r in context.roles) if(r.bound == null) {
				Context.warning("Role " + r.name + " isn't bound in its Context.", r.field.pos);
			}
		}
	}

	function replaceRole(role : DciRole) {
		for (roleMethod in role.roleMethods) {
			replaceInExpr(
				roleMethod.method.expr, 
				Option.Some(role), 
				Option.Some(roleMethod), 
				Option.Some(roleMethod.method)
			);
		}		
	}

	function replaceField(field : Field) {
		switch(field.kind) {
			case FVar(_, e): 
				if(e != null) replaceInExpr(e, Option.None, Option.None, Option.None);
			case FFun(f): 
				if(f.expr != null) replaceInExpr(f.expr, Option.None, Option.None, Option.Some(f));
			case FProp(_, _, _, e): 
				if(e != null) replaceInExpr(e, Option.None, Option.None, Option.None);
		}
	}

	function replaceInExpr(
		e : Expr, 
		currentRole : Option<DciRole>, 
		currentRoleMethod : Option<DciRoleMethod>, 
		currentFunction : Option<Function>
	) {
		var role : DciRole = switch currentRole {
			case None: null;
			case Some(role): role;
		};
		
		function testContractAccess(accessedRole : DciRole, contractMethod : Field, pos : Position) {
			if (accessedRole == role) return;
			
			if (!contractMethod.access.has(APrivate))
				Context.warning('Contract field ${accessedRole.name}.${contractMethod.name} accessed outside its Role.', pos);
			else
				Context.error('Cannot access private contract field ${accessedRole.name}.${contractMethod.name} outside its Role.', pos);
		}		
		
		// Test if a Role-object-contract or RoleMethod is accessed outside its Role
		function testRoleMethodAccess(accessedRole : DciRole, accessedRoleMethod : DciRoleMethod, pos : Position) {
			if (accessedRole == role) return;
			
			if (!accessedRoleMethod.isPublic) {
				Context.error('Cannot access private RoleMethod ${accessedRole.name}.${accessedRoleMethod.name} outside its Role.', pos);
			}
		}
		
		switch e.expr {
			/*
				 // role.roleMethod(...)
			case ECall({
				expr: EField({
					expr: EConst(CIdent(roleName)), 
					pos: _
				}, field), 
				pos: _
			}, params) 
			|	// this.role.roleMethod(...)
				ECall({
				expr: EField({
					expr: EField({
						expr: EConst(CIdent("this")),
						pos: _
					}, roleName),
					pos: _
				}, field), 
				pos: _
			}, params)
				if(roleName == "self" || roles.exists(roleName)): {
					if (roleName == "self") roleName = role.name;
					
					var role = roles.get(roleName);
					if(role.roleMethods.exists(function(rm) return rm.name == field)) {
						e.expr = ECall({
							expr: EConst(CIdent(roleName + "__" + field)), 
							pos: e.pos
						}, params);
					}
				}
			*/
			
			// role.roleMethod, this.role.roleMethod
			case EField({expr: EConst(CIdent(roleName)), pos: _}, field) | 
				 EField({expr: EField({expr: EConst(CIdent("this")), pos: _}, roleName), pos: _}, field)
				if (roleName == "self" || roles.exists(roleName)): {
					if (roleName == "self") roleName = role.name;
					var role = roles.get(roleName);
					
					var roleMethod = role.roleMethods.find(function(rm) return rm.name == field);
					if(roleMethod != null) {
						e.expr = EConst(CIdent(roleName + "__" + field));
						testRoleMethodAccess(role, roleMethod, e.pos);
					} else {
						var contractMethod = role.contract.find(function(c) return c.name == field);
						if (contractMethod != null) {
							testContractAccess(role, contractMethod, e.pos);
						}
					}
				}
			
			// self
			case EConst(CIdent(roleName)) if (roleName == "self"):
				e.expr = EConst(CIdent(role.name));
			
			case EConst(CString(s)) if (role != null && e.toString().charAt(0) == "'"):
				// Interpolation strings must be expanded and iterated, in case "self" is hidden there.
				e.expr = Format.format(e).expr;
			case EBinop(OpAssign, e1, e2): 
				// Potential role bindings, check if all are bound in same function
				setRoleBindPos(e1, currentRole, currentFunction);
				
			case EFunction(_, f) if (f.expr != null): 
				// Change function, to check for role bindings in same function
				replaceInExpr(f.expr, currentRole, currentRoleMethod, Some(f)); 
				return;
				
			case EDisplay(e, isCall):
				new Autocompletion(context, role).replaceDisplay(e, isCall);
				return;
				
			case _:
		}

		e.iter(replaceInExpr.bind(_, currentRole, currentRoleMethod, currentFunction));
	}

	// Returns true if a Role was successfully bound in the Expr.
	function setRoleBindPos(e : Expr, currentRole : Option<DciRole>, currentFunction : Option<Function>) : Bool {
		switch e.expr {
			case EField({expr: EConst(CIdent("this")), pos: _}, roleName) | EConst(CIdent(roleName))
				if (roles.exists(roleName)):
					// Set where the Role was bound in the Context.
					roles.get(roleName).bound = e.pos;
			case _:
				return false;
		}
		
		return switch(currentFunction) {
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
				true;
		}
	}
	
	/**
	 * Returns an array of identifiers from the current expression,
	 * or null if the expression isn't an EField or EConst.
	 */
	/*
	function extractIdentifier(e : Expr, currentRole : Option<DciRole>) : Null<Array<String>> {
		var fields = [];
		while (true) {
			switch(e.expr) {
				case EField(e2, field):
					var replace = switch(currentRole) {
						case None: field;
						case Some(r): (field == "self") ? r.name : field;
					}
					fields.unshift(replace);
					e = e2;

				case EConst(CIdent(s)):
					var replace = switch(currentRole)	{
						case None: s;
						case Some(r): (s == "self") ? r.name : s;
					}
					fields.unshift(replace);
					return fields;

				case _:	
					return null;
			}
		}
	}
	*/
	
	/**
	 * Given that console is a Role, rewriting 
	 * [console, cursor, pos] to [console__cursor, pos]
	 */
	/*
	function replaceIdentifiers(e : Expr, currentRoleOption : Option<DciRole>) : Bool {
		var fieldArray = extractIdentifier(e, currentRoleOption);
		if (fieldArray == null) return false;
		
		var currentRole : DciRole = switch currentRoleOption { 
			case Option.None: null;
			case Option.Some(role): role;
		}
		
		var hasThis = false;
		
		switch fieldArray[0] {
			case "this":
				if (currentRole != null && !Context.defined("display") && !DciContextBuilder.allowThisInRoleMethods)
					Context.error('"this" keyword is not allowed in RoleMethods, use "self" or reference the Role directly instead.', e.pos);
				else {
					// Remove "this" for easier array calculations.
					hasThis = true;
					fieldArray.shift();
				}

			case _:
		}
		
		var potentialRole = fieldArray[0];
		
		// Test if the field refers to a RoleMethod in the current Role, then prepend the current role.
		if (fieldArray.length == 1) {
			if (currentRole != null && (roleMethodNames.get(currentRole.name).has(potentialRole) ||
				currentRole.contract.find(function(f) return f.name == potentialRole) != null))
			{
				fieldArray.unshift(currentRole.name);
				// Reset potentialRole since the array has changed
				potentialRole = fieldArray[0];
			}
		} 
		
		if (fieldArray.length > 1) {
			var potentialRoleMethod = fieldArray[1];
			
			if(roles.exists(potentialRole)) {
				// Test if a Role-object-contract or RoleMethod is accessed outside its Role
				if (!Context.defined("display") && !DciContextBuilder.publicRoleAccess && 
					(currentRole == null || currentRole.name != potentialRole)) 
				{
					var role = roles.get(potentialRole);
					var contractMethod = role.contract.find(function(f) return f.name == potentialRoleMethod);
					if (contractMethod != null) {
						if (!contractMethod.access.has(APrivate))
							Context.warning('Contract field ${role.name}.$potentialRoleMethod accessed outside its Role.', e.pos);
						else
							Context.error('Cannot access private contract field ${role.name}.$potentialRoleMethod outside its Role.', e.pos);
					}
					
					var roleMethod = role.roleMethods.find(function(f) return f.name == potentialRoleMethod);
					if (roleMethod != null && !roleMethod.isPublic) {
						Context.error('Cannot access private RoleMethod ${role.name}.$potentialRoleMethod outside its Role.', e.pos);
					}
				}

				// Rewrite only if a RoleMethod is referred to
				if (roleMethodNames.get(potentialRole).has(potentialRoleMethod)) {
					// Concatename the first and second fields.
					fieldArray[1] = potentialRole + "__" + potentialRoleMethod;
					fieldArray.shift();
				}
			}
		}
		
		if (hasThis) fieldArray.unshift("this");

		//trace(fieldArray);
		
		e.expr = (macro $p{fieldArray}).expr;
		return true;
	}
	*/
}
#end
