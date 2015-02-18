package haxedci;
import haxe.ds.Option;
import sys.io.File;
import sys.io.FileOutput;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;

/**
 * Tests if roles are bound in the same function,
 * and replaces RoleMethod calls with its mangled representation.
 * i.e. this.console.cursor.pos => this.console__cursor.pos
 */
class RoleMethodReplacer
{
	public function new(field : Field, currentRole : Role, context : Dci) {
		this.field = field;
		this.context = context;
		this.currentRole = currentRole;
	}
	
	public function replace() {
		if (Context.defined("display")) {
			// A tricky case: When inside a RoleMethod the following RoleMethods aren't
			// found by the compiler. So it needs to be detected and manually resolved.
			//if (currentRole == null) return;
			switch(field.kind) {
				case FVar(_, e): if(e != null) e.iter(field_displayMergedType);
				case FFun(f): if(f.expr != null) f.expr.iter(field_displayMergedType);
				case FProp(_, _, _, e): if(e != null) e.iter(field_displayMergedType);
			}
		} else {
			switch(field.kind) {
				case FVar(_, e): if(e != null) e.iter(field_replace.bind(_, Option.None));
				case FFun(f): if(f.expr != null) f.expr.iter(field_replace.bind(_, Option.Some(f)));
				case FProp(_, _, _, e): if(e != null) e.iter(field_replace.bind(_, Option.None));
			}			
		}
	}
	
	var currentRole : Role;
	var field : Field;
	var context : Dci;
	
	function roles_bindRole(e : Expr, currentFunction : Option<Function>) {
		var fieldArray = field_extractArray(e);
		if (fieldArray == null) return;
		if (fieldArray[0] == "this") fieldArray.shift();		
		if (fieldArray.length != 1)	return;
		
		var role = context.roles.find(function(r) return r.name == fieldArray[0]);
		if (role == null) return;
		
		// Set where the Role was bound in the Context.
		role.bound = e.pos;

		//trace("Binding role " + fieldArray[0], e.pos);
		
		switch(currentFunction) {
			case None: Context.error('Role must be bound in a Context method!', e.pos);
			case Some(f):
				if (context.roleBindMethod == null) {
					context.roleBindMethod = f;
					context.lastRoleBindPos = e.pos;
				}
				else if (context.roleBindMethod != f) {
					Context.warning('Last Role assignment outside current method', context.lastRoleBindPos);
					Context.error('All Roles in a Context must be assigned in the same method.', e.pos);
				}
		}
	}

	function field_extractArray(e : Expr) {
		var fields = [];
		while (true) {
			switch(e.expr) {
				case EField(e2, field):
					var replace = (currentRole != null && field == Role.SELF) ? currentRole.name : field;
					fields.unshift(replace);
					e = e2;

				case EConst(c):
					switch(c) {
						case CIdent(s):
							var replace = (currentRole != null && s == Role.SELF) ? currentRole.name : s;
							fields.unshift(replace);
							return fields;
							
						case _: return null;
					}
					
				case _:	return null;
			}
		}
	}

	function field_displayMergedType(e : Expr) {
		switch(e.expr) {
			case EDisplay(e2, isCall):
				// Looking for self or a role in the current context.
				switch(e2) {
					case macro self:
						if (currentRole != null) {
							e2.expr = complexTypeExpr(
								new RoleObjectContractTypeMerger(currentRole).mergedType()
							);
						}
					case _:
						var ident = field_extractArray(e2);
						if (ident != null) {
							if (ident[0] == 'this' || ident[0] == 'context') ident.shift();
							if (ident.length == 1 && context.roles.exists(ident[0])) {
								e2.expr = complexTypeExpr(
									new RoleObjectContractTypeMerger(
										context.roles.get(ident[0])
									).mergedType()
								);
							}
						}
				}
			case _:
				e.iter(field_displayMergedType);
		}
	}
	
	static function complexTypeExpr(t : ComplexType) : ExprDef {
		return (macro { var __temp : $t = null; __temp; }).expr;
	}

	function field_replace(e : Expr, currentFunction : Option<Function>) {
		switch(e.expr) {
			case EBinop(op, e1, e2): switch op {
				case OpAssign: roles_bindRole(e1, currentFunction);
				case _:
			}

			case EField(_, _): 
				if (field_replaceField(e)) return;
				
			case _:
		}

		e.iter(field_replace.bind(_, currentFunction));
	}
	
	function field_replaceField(e : Expr) {
		var fieldArray = field_extractArray(e);
		if (fieldArray == null) return false;
		
		// Given that console is a Role, rewriting 
		// [this, console, cursor, pos] to [this, console__cursor, pos]
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
				var role = context.roles.get(field);
				if (role != null && role.roleMethods.exists(fieldArray[i + 1])) {
					newArray.push(Role.roleMethodFieldName(role.name, fieldArray[i+1]));
					skip = true; // Skip next field since it's now a part of the Role method call.
				} else {
					newArray.push(field);
				}
			}
		}
		
		if (fieldArray.length != newArray.length) {
			e.expr = field_build(newArray, newArray.length - 1, e.pos);
			return true;
		}
		
		return false;
	}
	
	function field_build(identifiers, i, pos) {
		if (i > 0)
			return EField({expr: field_build(identifiers, i - 1, pos), pos: pos}, identifiers[i]);
		else
			return EConst(CIdent(identifiers[i]));
	}

}
#end
