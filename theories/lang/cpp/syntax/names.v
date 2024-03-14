(*
 * Copyright (c) 2020 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 *)
Require Import stdpp.countable.
Require Import stdpp.strings.
Require Import bedrock.prelude.base.
Require Export bedrock.prelude.bytestring.

Set Primitive Projections.

#[local] Open Scope N_scope.

(* this represents names that exist in object files. *)
Definition obj_name : Set := bs.
Bind Scope bs_scope with obj_name.
#[global] Instance obj_name_eq: EqDecision obj_name := _.

Definition ident : Set := bs.
Bind Scope bs_scope with ident.
#[global] Instance ident_eq: EqDecision ident := _.

(* naming in C++ is complex.
 * - everything has a path, e.g. namespaces, classes, etc.
 *   examples: ::foo         -- the namespace `foo`
 *             ::Foo         -- the class/struct/enum `Foo`
 *             ::Foo<int, 1> -- templated class (template parameters are types *and* expressions)
 * - functions (but not variables) can be overloaded.
 *   (this is addressed via name mangling)
 * - types (classes, structs, typedefs, etc) are not mangled because they are
 *   not present in the object file
 * - there are also "unnamed" functions, e.g. constructors and destructors
 *)
Definition globname : Set := bs.
Bind Scope bs_scope with globname.
  (* these are mangled names. for consistency, we're going to
   * mangle everything.
   *)
#[global] Instance globname_eq: EqDecision globname := _.

(* local names *)
Definition localname : Set := ident.
Bind Scope bs_scope with localname.
#[global] Instance localname_eq: EqDecision localname := _.

(**
Identify an aggregate field.
XXX: is this used for function members? If so, rename.
[Member] is taken, but [member_name] or shortenings of
[member_qualified_name] could work. *)
Record field : Set :=
{ f_type : globname (* name of containing aggregate *)
; f_name : ident
}.
#[global] Instance field_eq: EqDecision field.
Proof. solve_decision. Defined.
