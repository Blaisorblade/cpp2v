(*
 * Copyright (c) 2020-2023 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 *)
From bedrock.prelude Require Import base list_numbers.
From bedrock.lang.cpp.syntax Require Import names expr types.

(** [type_of e] returns the type of the expression [e]. *)
Fixpoint type_of (e : Expr) : exprtype :=
  match e with
  | Econst_ref _ t
  | Evar _ t
  | Echar _ t => t
  | Estring vs t => Tarray (Qconst t) (1 + lengthN vs)
  | Eint _ t => t
  | Ebool _ => Tbool
  | Eunop _ _ t
  | Ebinop _ _ _ t => t
  | Eread_ref e => type_of e
  | Ederef _ t => t
  | Eaddrof e => Tptr (type_of e)
  | Eassign _ _ t
  | Eassign_op _ _ _ t
  | Epreinc _ t
  | Epostinc _ t
  | Epredec _ t
  | Epostdec _ t => t
  | Eseqand _ _ => Tbool
  | Eseqor _ _ => Tbool
  | Ecomma _ e2 => type_of e2
  | Ecall _ _ t
  | Ecast _ _ _ t
  | Emember _ _ t
  | Emember_call _ _ _ t
  | Eoperator_call _ _ _ t
  | Esubscript _ _ t
  | Esize_of _ t
  | Ealign_of _ t
  | Eoffset_of _ t
  | Econstructor _ _ t => t
  | Eimplicit e => type_of e
  | Eif _ _ _ _ t
  | Eif2 _ _ _ _ _ _ t
  | Ethis t => t
  | Enull => Tnullptr
  | Einitlist _ _ t
  | Eimplicit_init t => t
  | Enew _ _ aty _ _ => Tptr aty
  | Edelete _ _ _ _ => Tvoid
  | Eandclean e => type_of e
  | Ematerialize_temp e _ => type_of e
  | Eatomic _ _ t => t
  | Eva_arg _ t => t
  | Epseudo_destructor _ _ => Tvoid
  | Earrayloop_init _ _ _ _ _ t => t
  | Earrayloop_index _ t => t
  | Eopaque_ref _ _ t => t
  | Eunsupported _ _ t => t
  end.

(** [erase_qualifiers t] erases *all* qualifiers that occur everywhere in the type.

    NOTE we currently use this because we do not track [const]ness in the logic, this
    is somewhat reasonable because we often opt to express this in separation logic.
    And the type system also enforces some of the other criteria.
 *)
Fixpoint erase_qualifiers (t : type) : type :=
  match t with
  | Tpointer t => Tpointer (erase_qualifiers t)
  | Tref t => Tref (erase_qualifiers t)
  | Trv_ref t => Trv_ref (erase_qualifiers t)
  | Tnum _ _
  | Tchar_ _
  | Tbool
  | Tvoid
  | Tfloat_ _
  | Tnamed _
  | Tenum _ => t
  | Tarray t sz => Tarray (erase_qualifiers t) sz
  | @Tfunction cc ar t ts => Tfunction (cc:=cc) (ar:=ar) (erase_qualifiers t) (List.map erase_qualifiers ts)
  | Tmember_pointer cls t => Tmember_pointer cls (erase_qualifiers t)
  | Tqualified _ t => erase_qualifiers t
  | Tnullptr => Tnullptr
  | Tarch sz nm => Tarch sz nm
  end.

(** [drop_qualifiers t] drops all the *leading* qualifiers of the type [t].
    e.g. [drop_qualifiers (Qconst (Qmut t)) = t]
 *)
Fixpoint drop_qualifiers (t : type) : type :=
  match t with
  | Tqualified _ t => drop_qualifiers t
  | _ => t
  end.

Lemma is_qualified_erase_qualifiers ty : ~~ is_qualified (erase_qualifiers ty).
Proof. by induction ty. Qed.
#[global] Hint Resolve is_qualified_erase_qualifiers | 0 : core.

Lemma is_qualified_drop_qualifiers ty : ~~ is_qualified (drop_qualifiers ty).
Proof. by induction ty. Qed.
#[global] Hint Resolve is_qualified_drop_qualifiers | 0 : core.

Lemma erase_qualifiers_qual_norm' q t :
  erase_qualifiers t = qual_norm' (fun _ t => erase_qualifiers t) q t.
Proof. by elim: (qual_norm'_ok _ q t). Qed.
Lemma erase_qualifiers_qual_norm t :
  erase_qualifiers t = qual_norm (fun _ t => erase_qualifiers t) t.
Proof. apply erase_qualifiers_qual_norm'. Qed.
Lemma erase_qualifiers_decompose_type t :
  erase_qualifiers t = erase_qualifiers (decompose_type t).2.
Proof. by rewrite erase_qualifiers_qual_norm qual_norm_decompose_type. Qed.

Lemma drop_qualifiers_unqual t : ~~ is_qualified t -> drop_qualifiers t = t.
Proof. by destruct t; cbn; auto. Qed.

Lemma drop_qualifiers_qual_norm' q t : drop_qualifiers t = qual_norm' (fun _ t => t) q t.
Proof.
  elim: (qual_norm'_ok _ q t).
  { intros. by rewrite drop_qualifiers_unqual. }
  { done. }
Qed.
Lemma drop_qualifiers_qual_norm t : drop_qualifiers t = qual_norm (fun _ t => t) t.
Proof. apply drop_qualifiers_qual_norm'. Qed.
Lemma drop_qualifiers_decompose_type t : drop_qualifiers t = (decompose_type t).2.
Proof. by rewrite drop_qualifiers_qual_norm qual_norm_decompose_type. Qed.

Lemma erase_qualifiers_idemp t : erase_qualifiers (erase_qualifiers t) = erase_qualifiers t.
Proof.
  move: t. fix IHt 1=>t.
  destruct t as [| | | | | | | | |cc ar ret args| | | | | |]; cbn; auto with f_equal.
  { (* functions *) rewrite IHt. f_equal. induction args; cbn; auto with f_equal. }
Qed.
Lemma drop_qualifiers_idemp t : drop_qualifiers (drop_qualifiers t) = drop_qualifiers t.
Proof. by rewrite drop_qualifiers_unqual. Qed.

Lemma drop_erase_qualifiers t : drop_qualifiers (erase_qualifiers t) = erase_qualifiers t.
Proof. by rewrite drop_qualifiers_unqual. Qed.
Lemma erase_drop_qualifiers t : erase_qualifiers (drop_qualifiers t) = erase_qualifiers t.
Proof. induction t; cbn; auto. Qed.

#[deprecated(since="20230531", note="Use [drop_erase_qualifiers]")]
Notation drop_erase := drop_erase_qualifiers.
#[deprecated(since="20230531", note="Use [erase_drop_qualifiers]")]
Notation erase_drop := drop_erase_qualifiers.

Lemma unqual_drop_qualifiers ty tq ty' : drop_qualifiers ty <> Tqualified tq ty'.
Proof. by induction ty. Qed.
Lemma unqual_erase_qualifiers ty tq ty' : erase_qualifiers ty <> Tqualified tq ty'.
Proof. by induction ty. Qed.

Lemma erase_qualifiers_tqualified q t :
  erase_qualifiers (tqualified q t) = erase_qualifiers t.
Proof.
  induction (tqualified_ok q t).
  { by destruct (tqualified'_ok q t). }
  { done. }
Qed.
Lemma drop_qualifiers_tqualified q t :
  drop_qualifiers (tqualified q t) = drop_qualifiers t.
Proof.
  induction (tqualified_ok q t).
  { by destruct (tqualified'_ok q t). }
  { done. }
Qed.

(* Lemmas for all [type] constructors; in constructor order for easy review. *)
Lemma drop_qualifiers_Tptr : forall [ty ty'],
    drop_qualifiers ty = Tptr ty' -> erase_qualifiers ty = Tptr (erase_qualifiers ty').
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Tref : forall [ty ty'],
    drop_qualifiers ty = Tref ty' -> erase_qualifiers ty = Tref (erase_qualifiers ty').
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Trv_ref : forall [ty ty'],
    drop_qualifiers ty = Trv_ref ty' -> erase_qualifiers ty = Trv_ref (erase_qualifiers ty').
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Tnum : forall [ty sz sgn],
    drop_qualifiers ty = Tnum sz sgn -> erase_qualifiers ty = Tnum sz sgn.
Proof. by induction ty. Qed.
Lemma drop_qualifiers_Tchar_ : forall [ty ct],
    drop_qualifiers ty = Tchar_ ct -> erase_qualifiers ty = Tchar_ ct.
Proof. by induction ty. Qed.
Lemma drop_qualifiers_Tvoid : forall [ty],
    drop_qualifiers ty = Tvoid -> erase_qualifiers ty = Tvoid.
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Tarray : forall [ty ty' n],
    drop_qualifiers ty = Tarray ty' n -> erase_qualifiers ty = Tarray (erase_qualifiers ty') n.
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Tnamed : forall [ty n],
    drop_qualifiers ty = Tnamed n -> erase_qualifiers ty = Tnamed n.
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Tenum : forall [ty nm],
    drop_qualifiers ty = Tenum nm -> erase_qualifiers ty = Tenum nm.
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Tfunction : forall [ty c ar ty' tArgs],
    drop_qualifiers ty = @Tfunction c ar ty' tArgs ->
    erase_qualifiers ty = @Tfunction c ar (erase_qualifiers ty') (map erase_qualifiers tArgs).
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Tbool : forall [ty],
    drop_qualifiers ty = Tbool -> erase_qualifiers ty = Tbool.
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Tmember_pointer : forall [ty cls ty'],
    drop_qualifiers ty = Tmember_pointer cls ty' ->
    erase_qualifiers ty = Tmember_pointer cls (erase_qualifiers ty').
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
Lemma drop_qualifiers_Tfloat : forall [ty sz],
    drop_qualifiers ty = Tfloat_ sz -> erase_qualifiers ty = Tfloat_ sz.
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.
(* Omit Tqualified on purpose *)
Lemma drop_qualifiers_Tnullptr : forall [ty],
    drop_qualifiers ty = Tnullptr -> erase_qualifiers ty = Tnullptr.
Proof. induction ty; simpl; intros; try congruence; eauto. Qed.

(** simplify instances where you have [drop_qualifiers ty = Txxx ..] for some [Txxx]. *)
(* Same order as above, for easier review. *)
Ltac simpl_drop_qualifiers :=
  match goal with
  | H : drop_qualifiers _ = _ |- _ => first
          [ rewrite (drop_qualifiers_Tptr H)
          | rewrite (drop_qualifiers_Tref H)
          | rewrite (drop_qualifiers_Trv_ref H)
          | rewrite (drop_qualifiers_Tnum H)
          | rewrite (drop_qualifiers_Tchar_ H)
          | rewrite (drop_qualifiers_Tvoid H)
          | rewrite (drop_qualifiers_Tarray H)
          | rewrite (drop_qualifiers_Tnamed H)
          | rewrite (drop_qualifiers_Tenum H)
          | rewrite (drop_qualifiers_Tfunction H)
          | rewrite (drop_qualifiers_Tbool H)
          | rewrite (drop_qualifiers_Tmember_pointer H)
          | rewrite (drop_qualifiers_Tfloat H)
          | rewrite (drop_qualifiers_Tnullptr H)
          ]
  end.


(** [unptr t] returns the type of the object that a value of type [t] points to
    or [None] if [t] is not a pointer type.
 *)
Definition unptr (t : type) : option type :=
  match drop_qualifiers t with
  | Tptr p => Some p
  | _ => None
  end.

(** [drop_reference t] drops leading reference and qualifiers to get the underlying
    type.
 *)
Fixpoint drop_reference (t : type) : exprtype :=
  match t with
  | Tref t => drop_reference t
  | Trv_ref t => drop_reference t
  | Tqualified q t => drop_reference t
  | _ => t
  end.

Lemma drop_reference_qual_norm t :
  drop_reference t = qual_norm (fun _ t => drop_reference t) t.
Proof. by elim: (qual_norm_ok _ _). Qed.
Lemma drop_reference_decompose_type t :
  drop_reference t = let p := decompose_type t in drop_reference p.2.
Proof. by rewrite drop_reference_qual_norm qual_norm_decompose_type. Qed.

(** [class_name t] returns the name of the class that this type refers to
 *)
Definition class_name (t : type) : option globname :=
  match drop_qualifiers t with
  | Tnamed gn => Some gn
  | _ => None
  end.

(** [is_arithmetic ty] states whether [ty] is an arithmetic type *)
Definition is_arithmetic (ty : type) : bool :=
  match drop_qualifiers ty with
  | Tnum _ _
  | Tchar_ _
  | Tenum _
  | Tbool => true
  | _ => false
  end.

(** [is_pointer ty] is [true] if [ty] is a pointer type *)
Definition is_pointer (ty : type) : bool :=
  match drop_qualifiers ty with
  | Tptr _ => true
  | _ => false
  end.

Lemma is_pointer_not_arithmetic : forall ty, is_pointer ty = true -> is_arithmetic ty = false.
Proof. induction ty; simpl; intros; eauto. Qed.
Lemma is_arithmetic_not_pointer : forall ty, is_arithmetic ty = true -> is_pointer ty = false.
Proof. induction ty; simpl; intros; eauto. Qed.

(** Formalizes https://eel.is/c++draft/basic.types.general#term.scalar.type.
  *)
Definition scalar_type (ty : type) : bool :=
  match drop_qualifiers ty with
  | Tnullptr | Tptr _
  | Tmember_pointer _ _
  | Tfloat_ _
  | Tchar_ _
  | Tbool
  | Tnum _ _ | Tenum _ => true
  | _ => false
  end.
Lemma scalar_type_erase_drop ty :
  scalar_type (erase_qualifiers ty) = scalar_type (drop_qualifiers ty).
Proof. by induction ty. Qed.

(** [is_value_type t] returns [true] if [t] has value semantics.
    A value type is one that can be represented by [val].

    NOTE: The only difference between a value type and a scalar type is
    that [Tvoid] is a value type and not a scalar type.
 *)
Definition is_value_type (t : type) : bool :=
  match drop_qualifiers t with
  | Tnum _ _
  | Tchar_ _
  | Tbool
  | Tptr _
  | Tnullptr
  | Tfloat_ _
  | Tmember_pointer _ _
  (**
  NOTE: In C++ the the underlying type of an enumeration must be an
  integral type. This definition presuppposes [t] a valid enumeration.
  *)
  | Tenum _ (* enum types are value types *)
  | Tvoid => true
  | _ => false
  end.

Lemma is_value_type_erase_qualifiers ty :
  is_value_type (erase_qualifiers ty) = is_value_type ty.
Proof. induction ty; cbn; auto. Qed.
Lemma is_value_type_drop_qualifiers ty :
  is_value_type (drop_qualifiers ty) = is_value_type ty.
Proof. induction ty; cbn; auto. Qed.

Lemma is_value_type_qual_norm' q t :
  is_value_type t = qual_norm' (fun _ t' => is_value_type t') q t.
Proof. by elim: (qual_norm'_ok _ q t). Qed.
Lemma is_value_type_qual_norm t :
  is_value_type t = qual_norm (fun _ t' => is_value_type t') t.
Proof. apply is_value_type_qual_norm'. Qed.
Lemma is_value_type_decompose_type t :
  is_value_type t = is_value_type (decompose_type t).2.
Proof. by rewrite is_value_type_qual_norm qual_norm_decompose_type. Qed.

(**
[is_reference_type t] returns [true] if [t] is a (possibly
cv-qualified) reference type.
*)
Definition is_reference_type (t : type) : bool :=
  is_ref (drop_qualifiers t).

Lemma value_type_non_ref {ty} : is_value_type ty -> ~~ is_reference_type ty.
Proof. by induction ty. Qed.

Lemma is_reference_type_erase_qualifiers t :
  is_reference_type (erase_qualifiers t) = is_reference_type t.
Proof. induction t; cbn; auto. Qed.
Lemma is_reference_type_drop_qualifiers t :
  is_reference_type (drop_qualifiers t) = is_reference_type t.
Proof. induction t; cbn; auto. Qed.

Lemma is_reference_type_qual_norm' q t :
  is_reference_type t = qual_norm' (fun _ t => is_reference_type t) q t.
Proof. by elim: (qual_norm'_ok _ q t). Qed.
Lemma is_reference_type_qual_norm t :
  is_reference_type t = qual_norm (fun _ t => is_reference_type t) t.
Proof. apply is_reference_type_qual_norm'. Qed.
Lemma is_reference_type_decompose_type t :
  is_reference_type t = is_reference_type (decompose_type t).2.
Proof. by rewrite is_reference_type_qual_norm qual_norm_decompose_type. Qed.

(**
[as_ref' f x t] applies [f u] if [t] is a (possibly cv-qualified)
reference type with underlying type [u], defaulting to [x] if [t] is
not a reference type.

The special cases [as_ref t : type] and [as_ref_option : option type]
return the underlying type [u] (defaulting, respectively, to a dummy
type and to [None]).
*)

Definition as_ref' {A} (f : exprtype -> A) (x : A) (t : type) : A :=
  if drop_qualifiers t is (Tref u | Trv_ref u) then f u else x.
Notation as_ref := (as_ref' (fun u => u) Tvoid).
Notation as_ref_option := (as_ref' Some None).

Lemma as_ref'_erase_qualifiers {A} (f : exprtype -> A) (x : A) t :
  as_ref' f x (erase_qualifiers t) = as_ref' (f ∘ erase_qualifiers) x t.
Proof. induction t; cbn; auto. Qed.
Lemma as_ref_erase_qualifiers t :
  as_ref (erase_qualifiers t) = erase_qualifiers (as_ref t).
Proof. induction t; cbn; auto. Qed.

Section as_ref'.
  Context {A : Type} (f : exprtype -> A) (x : A).
  #[local] Notation as_ref' := (as_ref' f x).

  Lemma as_ref_drop_qualifiers t : as_ref' (drop_qualifiers t) = as_ref' t.
  Proof. induction t; cbn; auto. Qed.
  Lemma as_ref_qual_norm' q t : as_ref' t = qual_norm' (fun _ t => as_ref' t) q t.
  Proof. by elim: (qual_norm'_ok _ q t). Qed.
  Lemma as_ref_qual_norm t : as_ref' t = qual_norm (fun _ t => as_ref' t) t.
  Proof. apply as_ref_qual_norm'. Qed.
  Lemma as_ref_decompose_type t : as_ref' t = as_ref' (decompose_type t).2.
  Proof. by rewrite as_ref_qual_norm qual_norm_decompose_type. Qed.
End as_ref'.

(**
[is_aggregate_type t] returns [true] if [t] is a (possibly qualified)
structure or array type.
*)
Definition is_aggregate_type (ty : type) : bool :=
  match drop_qualifiers ty with
  | Tnamed _ | Tarray _ _ => true
  | _ => false
  end.

Lemma is_aggregate_type_drop_qualifiers ty :
  is_aggregate_type (drop_qualifiers ty) = is_aggregate_type ty.
Proof.
  by rewrite /is_aggregate_type drop_qualifiers_idemp.
Qed.
Lemma is_aggregate_type_erase_qualifiers ty :
  is_aggregate_type (erase_qualifiers ty) = is_aggregate_type ty.
Proof. by induction ty. Qed.

Lemma is_aggregate_type_qual_norm' cv ty :
  is_aggregate_type ty = qual_norm' (fun _ ty' => is_aggregate_type ty') cv ty.
Proof. by elim: (qual_norm'_ok _ _ _). Qed.
Lemma is_aggregate_type_qual_norm ty :
  is_aggregate_type ty = qual_norm (fun _ ty' => is_aggregate_type ty')  ty.
Proof. apply is_aggregate_type_qual_norm'. Qed.
Lemma is_aggregate_type_decompose_type ty :
  is_aggregate_type ty = is_aggregate_type (decompose_type ty).2.
Proof.
  by rewrite is_aggregate_type_qual_norm qual_norm_decompose_type.
Qed.

Lemma aggregate_type_non_ref ty : is_aggregate_type ty -> ~~ is_reference_type ty.
Proof. by induction ty. Qed.
Lemma aggregate_type_non_val ty : is_aggregate_type ty -> ~~ is_value_type ty.
Proof. by induction ty. Qed.

(**
Setting aside uninstantiated template arguments, there's a total
function from expressions to value categories.
*)
Definition UNEXPECTED_valcat {A} (tm : A) : ValCat.
Proof. exact Prvalue. Qed.

(**
The value category of an explicit cast to type [t] or a call to a
function returning type [t] or a [__builtin_va_arg] of type [t].
*)
Definition valcat_from_type (t : decltype) : ValCat :=
  (*
  Dropping qualifiers may not be necessary. Cppreference says
  "Reference types cannot be cv-qualified at the top level".
  *)
  match drop_qualifiers t with
  | Tref _
  | Trv_ref (@Tfunction _ _ _ _) => Lvalue
  | Trv_ref _ => Xvalue
  | _ => Prvalue
  end.

(* See <https://eel.is/c++draft/expr.call#13> *)
Definition valcat_from_function_type (t : functype) : ValCat :=
  match t with
  | @Tfunction _ _ ret _ => valcat_from_type ret
  | _ => UNEXPECTED_valcat t
  end.

Fixpoint valcat_of (e : Expr) : ValCat :=
  match e with
  | Econst_ref _ _ => Prvalue
  | Evar _ _ => Lvalue
  | Echar _ _ => Prvalue
  | Estring _ _ => Lvalue
  | Eint _ _ => Prvalue
  | Ebool _ => Prvalue
  | Eunop _ _ _ => Prvalue
  | Ebinop op e1 _ _ =>
    match op with
    | Bdotp =>
      (**
      The value category of [e1.*e2] is (i) that of [e1] (xvalue or
      lvalue) when [e2] points to a field and (ii) prvalue when [e2]
      points to a method.

      We need only address (i) here because when [e2] is a method, the
      result of [e1.*e2] must be immediately applied, and cpp2v emits
      [Emember_call] rather than [Ebinop] for indirect method calls.

      https://www.eel.is/c++draft/expr.mptr.oper#6
      *)
      match e1 with
      | Eread_ref _ => Lvalue
      | Ematerialize_temp _ _ => Xvalue
      | _ => UNEXPECTED_valcat e
      end
    | Bdotip => Lvalue	(* derived from [Bdotp] *)
    | _ => Prvalue
    end
  | Eread_ref e =>
    (*
    cpp2v ensures [e] is either a variable [Evar] or a field [Emember]
    with reference type. According to cppreference, "the name of a
    variable, [...], or a data member, regardless of type" is an
    lvalue.
    *)
    Lvalue
  | Ederef _ _ => Lvalue
  | Eaddrof _ => Prvalue
  | Eassign _ _ _ => Lvalue
  | Eassign_op _ _ _ _ => Lvalue
  | Epreinc _ _ => Lvalue
  | Epostinc _ _ => Prvalue
  | Epredec _ _ => Lvalue
  | Epostdec _ _ => Prvalue
  | Eseqand _ _ => Prvalue
  | Eseqor _ _ => Prvalue
  | Ecomma _ e2 => valcat_of e2
  | Ecast _ _ vc _ => vc
  | Ecall f _ _ =>
    match f with
    | Ecast Cfun2ptr _ _ (Tptr t) => valcat_from_function_type t
    | _ => UNEXPECTED_valcat e
    end
  | Emember e _ _ => valcat_of e
  | Emember_call f _ _ _ =>
    match f with
    | inl (_, _, t)
    | inr (Ecast Cl2r _  _ (Tmember_pointer _ t)) => valcat_from_function_type t
    | _ => UNEXPECTED_valcat e
    end
  | Eoperator_call _ f _ _ =>
    match f with
    | operator_impl.Func _ t => valcat_from_function_type t
    | operator_impl.MFunc _ _ ft => valcat_from_function_type ft
    end

  | Esubscript e1 e2 _ =>
    (**
    Neither operand ever has type [Tarray _ _] due to implicitly
    inserted array-to-pointer conversions. To compute the right value
    category, we skip over such conversions.
    *)
    let valcat_of_array (ar : Expr) : ValCat :=
      match valcat_of ar with
      | Lvalue => Lvalue
      | Prvalue | Xvalue => Xvalue
      end
    in
    let valcat_of_base (ei : Expr) : ValCat :=
      match ei with
      | Ecast Carray2ptr ar _ _ => valcat_of_array ar
      | _ => Lvalue
      end
    in
    match drop_qualifiers (type_of e1) with
    | Tptr _ => valcat_of_base e1
    | _ => valcat_of_base e2
    end
  | Esize_of _ _ => Prvalue
  | Ealign_of _ _ => Prvalue
  | Eoffset_of _ _ => Prvalue
  | Econstructor _ _ _ => Prvalue (* init *)
  | Eimplicit e => valcat_of e
  | Eif _ e1 e2 vc _ => vc
  | Eif2 _ _ _ _ _ vc _ => vc
  | Ethis _ => Prvalue
  | Enull => Prvalue
  | Einitlist _ _ _ => Prvalue (* operand | init *)
  | Eimplicit_init _ =>
    (**
    "References cannot be value-initialized".

    https://en.cppreference.com/w/cpp/language/value_initialization
    *)
    Prvalue
  | Enew _ _ _ _ _ => Prvalue
  | Edelete _ _ _ _ => Prvalue
  | Eandclean e => valcat_of e
  | Ematerialize_temp _ vc => vc
  | Eatomic _ _ _ => Prvalue
  | Eva_arg _ t => valcat_from_type t
  | Epseudo_destructor _ _ => Prvalue
  | Earrayloop_init _ _ _ _ _ _ => Prvalue (* init *)
  | Earrayloop_index _ _ => Prvalue
  | Eopaque_ref _ vc _ => vc
  | Eunsupported _ vc _ => vc
  end.
#[global] Arguments valcat_of !_ / : simpl nomatch, assert.

#[projections(primitive)]
Record vctype : Set := VCType { vctype_type : exprtype; vctype_valcat : ValCat }.
Add Printing Constructor vctype.

#[global] Instance vctype_eq_dec : EqDecision vctype.
Proof. solve_decision. Defined.

#[global] Instance vctype_countable : Countable vctype.
Proof.
  apply (inj_countable'
    (fun r => (r.(vctype_type), r.(vctype_valcat)))
    (fun p => VCType p.1 p.2)
  ).
  abstract (by intros []).
Defined.

Definition vctype_of (e : Expr) : vctype :=
  VCType (type_of e) (valcat_of e).

Lemma vctype_of_type e : vctype_type (vctype_of e) = type_of e.
Proof. done. Qed.
Lemma vctype_of_valcat e : vctype_valcat (vctype_of e) = valcat_of e.
Proof. done. Qed.
Lemma vctype_of_inv e vt :
  vctype_of e = vt ->
  type_of e = vt.(vctype_type) /\ valcat_of e = vt.(vctype_valcat).
Proof. by intros <-. Qed.
