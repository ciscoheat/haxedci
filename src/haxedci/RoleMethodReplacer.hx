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
	var displayMode : Bool;

	public function new(context : DciContext) {
		this.context = context;
		this.displayMode = Context.defined("display");
		
		for (role in context.roles)
			this.roles.set(role.name, role);
	}
	
	public function replaceAll() {
		for (role in roles) replaceRole(role);
		for (field in context.normalFields) {
			replaceField(field);
		}
		
		// After all replacement is done, test if all roles are bound.
		if (!displayMode) {
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

		// Test if a contract field is accessed outside its Role
		function testContractAccess(accessedRole : DciRole, contractMethod : Field, pos : Position) {
			if (accessedRole == role) return;
			
			if (contractMethod.access.has(APublic))
				Context.warning('Contract field ${accessedRole.name}.${contractMethod.name} ' + 
					'accessed outside its Role.', pos);
			else
				Context.error('Cannot access private contract field ' + 
				'${accessedRole.name}.${contractMethod.name} outside its Role.', pos);
		}		
		
		// Test if a RoleMethod is accessed outside its Role
		function testRoleMethodAccess(accessedRole : DciRole, accessedRoleMethod : DciRoleMethod, pos : Position) {
			if (accessedRole == role) return;
			
			if (!accessedRoleMethod.isPublic) {
				Context.error('Cannot access private RoleMethod ' + 
				'${accessedRole.name}.${accessedRoleMethod.name} outside its Role.', pos);
			}
		}
		
		switch e.expr {
			// role.roleMethod, this.role.roleMethod
			case EField({expr: EConst(CIdent(roleName)), pos: _}, field) | 
				 EField({expr: EField({expr: EConst(CIdent("this")), pos: _}, roleName), pos: _}, field)
			if (roleName == "self" || roles.exists(roleName)):
				try {
					if (roleName == "self") roleName = role.name;
					var role = roles.get(roleName);						
					var roleMethod = role.roleMethods.find(function(rm) return rm.name == field);

					if(roleMethod != null) {
						e.expr = EConst(CIdent(roleName + "__" + field));
						if(!displayMode) testRoleMethodAccess(role, roleMethod, e.pos);
					} else {
						var contractMethod = role.contract.find(function(c) return c.name == field);
						if (contractMethod != null) {
							if(!displayMode) testContractAccess(role, contractMethod, e.pos);
						}
					}
				} catch(e : Dynamic) {
					// Autocompletion have problems with RoleMethods,
					// since it has no full Context. Roles can be null in a RoleMethod.
					if(!Context.defined('display')) throw e;
				}
			
			// self
			case EConst(CIdent(roleName)) if (roleName == "self"):
				if(role == null && Context.defined('display')) {
					// Same autocompletion problem here, Roles can be null in a RoleMethod.
				} else {
					e.expr = EConst(CIdent(role.name));
				}

			// Direct roleMethod or contract access
			case EConst(CIdent(field)) if (role != null):
				var rmCall = role.roleMethods.find(function(rm) return rm.name == field);
				if (rmCall != null) e.expr = EConst(CIdent(role.name + "__" + field));
				else {
					var contractCall = role.contract.find(function(c) return c.name == field);
					if (contractCall != null) {
						e.expr = EField({expr: EConst(CIdent(role.name)), pos: e.pos}, field);
					}
				}
				
			// Direct roleMethod or contract call
			case ECall({expr: EConst(CIdent(field)), pos: _}, params) if(role != null):
				var rmCall = role.roleMethods.find(function(rm) return rm.name == field);
				if (rmCall != null) { 
					e.expr = ECall({expr: EConst(CIdent(role.name + "__" + field)), pos: e.pos}, params);
				}
				else {
					var contractCall = role.contract.find(function(c) return c.name == field);
					if (contractCall != null) e.expr = ECall({
						expr: EField({expr: EConst(CIdent(role.name)), pos: e.pos}, field),
						pos: e.pos
					}, params);
				}

			// Interpolation strings must be expanded and iterated, in case "self" is hidden there.
			case EConst(CString(s)) if (role != null && e.toString().charAt(0) == "'"):
				e.expr = Format.format(e).expr;
				
			// Potential role bindings, check if all are bound in same function
			case EBinop(OpAssign, e1, e2): 
				setRoleBindPos(e1, currentRole, currentFunction);
				
			// Change function, to check for role bindings in same function
			case EFunction(_, f) if (f.expr != null): 
				replaceInExpr(f.expr, currentRole, currentRoleMethod, Some(f)); 
				return;

			// Autocompletion is different depending on where in the context you are.
			case EDisplay(e, isCall):
				new Autocompletion(context, currentRole, currentRoleMethod).replaceDisplay(e, isCall);
				return;
				
			case _:
		}

		e.iter(replaceInExpr.bind(_, currentRole, currentRoleMethod, currentFunction));
	}

	// Returns true if a Role was successfully bound in the Expr.
	function setRoleBindPos(e : Expr, currentRole : Option<DciRole>, currentFunction : Option<Function>) {
		switch e.expr {
			case EField({expr: EConst(CIdent("this")), pos: _}, roleName) | EConst(CIdent(roleName))
				if (roles.exists(roleName)):
					// Set where the Role was bound in the Context.
					roles.get(roleName).bound = e.pos;
			case _:
				return;
		}
		
		switch(currentFunction) {
			case None: 
				Context.error('Role must be bound in a Context method!', e.pos);
				
			// set roleBindFunction, but create an error if it already exists somewhere else
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
	}
}
#end
