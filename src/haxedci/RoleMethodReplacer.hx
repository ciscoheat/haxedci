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
		
		//trace("=== Fields rewritten for Context ==="); for (role in roles) for(rm in role.roleMethods) trace(rm.method.expr.toString());
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
		var role = switch currentRole {
			case None: null;
			case Some(role): role;
		};
		
		switch(e.expr) {
			case EFunction(_, f) if (f.expr != null): 
				// Change function, to check for role bindings is same function
				replaceInExpr(f.expr, currentRole, Some(f)); 
				return;
			case EField(_, _) | EConst(CIdent(_)):
				// Fields could be changed to role__method
				replaceIdentifiers(e, currentRole);
			case EConst(CString(s)) if (role != null && e.toString().charAt(0) == "'"):
				// Interpolation strings must be expanded and iterated, in case "self" is hidden there.
				e.expr = Format.format(e).expr;
			case EBinop(OpAssign, e1, e2): 
				// Potential role bindings, check if all are bound in same function
				setRoleBindPos(e1, currentRole, currentFunction);
			case _:
		}

		e.iter(replaceInExpr.bind(_, currentRole, currentFunction));
	}

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
	
	/**
	 * Given that console is a Role, rewriting 
	 * [console, cursor, pos] to [console__cursor, pos]
	 */
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
				if (currentRole != null && !DciContextBuilder.allowThisInRoleMethods)
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
				if (!DciContextBuilder.publicRoleAccess && 
					(currentRole == null || currentRole.name != potentialRole)) 
				{
					var role = roles.get(potentialRole);
					var contractMethod = role.contract.find(function(f) return f.name == potentialRoleMethod);
					if (contractMethod != null) {
						Context.warning('Contract field ${role.name}.$potentialRoleMethod accessed outside its Role.', e.pos);
					}
					
					var roleMethod = role.roleMethods.find(function(f) return f.name == potentialRoleMethod);
					if (roleMethod != null && !roleMethod.isPublic) {
						Context.error('Cannot access RoleMethod ${role.name}.$potentialRoleMethod outside its Role. ' + 
							'You can make it public if needed.', e.pos);
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
}
#end
