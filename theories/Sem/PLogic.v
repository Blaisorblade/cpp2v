(*
 * Copyright (C) BedRock Systems Inc. 2019 Gregory Malecha
 *
 * SPDX-License-Identifier:AGPL-3.0-or-later
 *)
Require Import Coq.Classes.Morphisms.
Require Import Coq.NArith.BinNat.
Require Import Coq.ZArith.BinInt.
Require Import Coq.Strings.String.

From Cpp Require Import ChargeCompat.
From Cpp.Sem Require Import Logic Semantics.
From iris.bi Require Export monpred.
From Cpp Require Import Ast.

Local Open Scope string_scope.

(* representations are predicates over a location, they should be used to
 * assert properties of the heap
 *)
(* todo(gmm): `addr : val` -> `addr : ptr` *)
Instance val_inhabited : Inhabited val.
Proof. constructor. apply (Vint 0). Qed.

Instance val_rel : SqSubsetEq val.
Proof.
  unfold SqSubsetEq.
  unfold relation.
  apply eq.
Defined.

Instance val_rel_preorder : PreOrder (⊑@{val}).
Proof.
  unfold sqsubseteq. unfold val_rel.
  apply base.PreOrder_instance_0.
Qed.

Canonical Structure val_bi_index : biIndex :=
  BiIndex val val_inhabited val_rel val_rel_preorder.

Definition Rep Σ := (monPred val_bi_index (mpredI Σ)).
Definition RepI Σ := (monPredI val_bi_index (mpredI Σ)).
Definition RepSI Σ := (monPredSI val_bi_index (mpredSI Σ)).

Lemma monPred_at_persistent_inv {V bi} (P : monPred V bi) :
  (∀ i, Persistent (P i)) → Persistent P.
Proof. intros HP. constructor=> i. MonPred.unseal. apply HP. Qed.


Lemma monPred_at_timeless_inv {V sbi} (P : monPredSI V sbi) :
  (∀ i, Timeless (P i)) → Timeless P.
Proof. intros HP. constructor=> i. MonPred.unseal. apply HP. Qed.

(* locations are predicates over a location and are used to do address
 * arithmetic.
 * - note(gmm): they are always computable from the program except for when
 *   they use field and the layout of a non-standard class or when they
 *   mention local variables.
 *)
Definition Loc Σ := (monPred val_bi_index (mpredI Σ)).
Definition LocI Σ := (monPredI val_bi_index (mpredI Σ)).
Definition LocSI Σ := (monPredSI val_bi_index (mpredSI Σ)).

Definition Offset Σ := (monPred val_bi_index (monPredI val_bi_index (mpredI Σ))).
Definition OffsetI Σ := (monPredI val_bi_index (monPredI val_bi_index (mpredI Σ))).
Definition OffsetSI Σ := (monPredSI val_bi_index (monPredSI val_bi_index (mpredSI Σ))).

Section with_Σ.
Context {Σ : gFunctors}.

Local Notation mpred := (mpred Σ) (only parsing).
Local Notation Rep := (Rep Σ) (only parsing).
Local Notation Loc := (Loc Σ) (only parsing).
Local Notation Offset := (Offset Σ) (only parsing).

Local Ltac solve_Rep_persistent X :=
  intros;
  rewrite X;
  constructor; apply monPred_at_persistent_inv;
  apply _.
Local Ltac solve_Loc_persistent X :=
  intros;
  rewrite X;
  constructor; apply monPred_at_persistent_inv;
  apply _.
Local Ltac solve_Offset_persistent X :=
  intros;
  rewrite X;
  constructor; apply monPred_at_persistent_inv;
  constructor; apply monPred_at_persistent_inv;
  apply _.

Local Ltac solve_Rep_timeless X :=
  intros;
  rewrite X;
  constructor; apply monPred_at_timeless_inv;
  apply _.
Local Ltac solve_Loc_timeless X :=
  intros;
  rewrite X;
  constructor; apply monPred_at_timeless_inv;
  apply _.
Local Ltac solve_Offset_timeless X :=
  intros;
  rewrite X;
  constructor; apply monPred_at_timeless_inv;
  constructor; apply monPred_at_timeless_inv;
  apply _.

Definition as_Rep (P : val -> mpred) : Rep := MonPred P _.
Definition as_Loc (P : val -> mpred) : Loc := MonPred P _.
Definition as_Offset (P : val -> val -> mpred) : Offset := MonPred (fun v => MonPred (P v) _) _.

Lemma Rep_equiv_ext_equiv : forall P Q : Rep,
    (forall x, P x -|- Q x) ->
    P -|- Q.
Proof.
  split; red; simpl; eapply H.
Qed.

Definition LocEq (l1 l2 : Loc) : Prop :=
  forall (x y : val), (l1 x) //\\ (l2 y) |-- [| x = y |].

(* absolute locations *)
Definition _eq_def (a : val) : Loc :=
  as_Loc (fun p => [| p = a |]).
Definition _eq_aux : seal (@_eq_def). by eexists. Qed.
Definition _eq := _eq_aux.(unseal).
Definition _eq_eq : @_eq = _ := _eq_aux.(seal_eq).

Global Instance _eq_persistent : Persistent (_eq a).
Proof. solve_Loc_persistent _eq_eq. Qed.
Global Instance _eq_Timeless : Timeless (_eq a).
Proof. solve_Loc_timeless _eq_eq. Qed.

(* note(gmm): this is *not* duplicable *)
Definition _local_def (r : region) (x : ident) : Loc :=
  as_Loc (fun v => Exists p, [| v = Vptr p |] ** local_addr r x p).
Definition _local_aux : seal (@_local_def). by eexists. Qed.
Definition _local := _local_aux.(unseal).
Definition _local_eq : @_local = _ := _local_aux.(seal_eq).

Global Instance _local_persistent : Persistent (_local r x).
Proof. solve_Loc_persistent _local_eq. Qed.

Definition _this_def (r : region) : Loc :=
  _local r "#this".
Definition _this_aux : seal (@_this_def). by eexists. Qed.
Definition _this := _this_aux.(unseal).
Definition _this_eq : @_this = _ := _this_aux.(seal_eq).

Global Instance _this_persistent : Persistent (_this r).
Proof. rewrite _this_eq. apply _. Qed.

Definition _result_def (r : region) : Loc :=
  _local r "#result".
Definition _result_aux : seal (@_result_def). by eexists. Qed.
Definition _result := _result_aux.(unseal).
Definition _result_eq : @_result = _ := _result_aux.(seal_eq).

Global Instance _result_persistent : Persistent (_result r).
Proof. rewrite _result_eq. apply _. Qed.

Definition _global_def (x : obj_name) : Loc :=
  as_Loc (fun v => Exists p, [| v = Vptr p |] **
                    with_genv (fun env => [| glob_addr env x p |])).
Definition _global_aux : seal (@_global_def). by eexists. Qed.
Definition _global := _global_aux.(unseal).
Definition _global_eq : @_global = _ := _global_aux.(seal_eq).

Global Instance _global_persistent : Persistent (_global r).
Proof. solve_Loc_persistent _global_eq. Qed.

(* offsets *)
Definition _field_def (f : field) : Offset :=
  as_Offset (fun from to =>
       with_genv (fun g => Exists off : Z,
       [| offset_of g (Tref f.(f_type)) f.(f_name) off |] **
       [| offset_ptr from off = to |])).
Definition _field_aux : seal (@_field_def). by eexists. Qed.
Definition _field := _field_aux.(unseal).
Definition _field_eq : @_field = _ := _field_aux.(seal_eq).

Global Instance _field_persistent f : Persistent (_field f).
Proof. solve_Offset_persistent _field_eq. Qed.

Definition _sub_def (t : type) (i : Z) : Offset :=
  as_Offset (fun from to =>
    Exists sz, with_genv (fun prg => [| size_of prg t sz |]) **
                         [| to = offset_ptr from (i * Z.of_N sz) |]).
Definition _sub_aux : seal (@_sub_def). by eexists. Qed.
Definition _sub := _sub_aux.(unseal).
Definition _sub_eq : @_sub = _ := _sub_aux.(seal_eq).

Global Instance _sub_persistent t i : Persistent (_sub t i).
Proof. solve_Offset_persistent _sub_eq. Qed.

(* this represents static_cast *)
Definition _super_def (sub super : globname) : Offset :=
  as_Offset (fun base addr =>
             Exists off, with_genv (fun prg => [| parent_offset prg sub super off |]) **
                                   [| addr = offset_ptr base off |]).
Definition _super_aux : seal (@_super_def). by eexists. Qed.
Definition _super := _super_aux.(unseal).
Definition _super_eq : @_super = _ := _super_aux.(seal_eq).

Global Instance _super_persistent sub sup : Persistent (_super sub sup).
Proof. solve_Offset_persistent _super_eq. Qed.

Definition _deref_def (ty : type) q : Offset :=
  as_Offset (fun from to =>
               tptsto ty q from to ** [| has_type from (Tpointer ty) |]).
Definition _deref_aux : seal (@_deref_def). by eexists. Qed.
Definition _deref := _deref_aux.(unseal).
Definition _deref_eq : @_deref = _ := _deref_aux.(seal_eq).

Definition _id_def : Offset :=
  as_Offset (fun a b => [| a = b |]).
Definition _id_aux : seal (@_id_def). by eexists. Qed.
Definition _id := _id_aux.(unseal).
Definition _id_eq : @_id = _ := _id_aux.(seal_eq).

Global Instance _id_persistent : Persistent (_id).
Proof. solve_Offset_persistent _id_eq. Qed.

Definition _dot_def (o1 o2 : Offset) : Offset :=
  as_Offset (fun a c => Exists b, o1 a b ** o2 b c).
Definition _dot_aux : seal (@_dot_def). by eexists. Qed.
Definition _dot := _dot_aux.(unseal).
Definition _dot_eq : @_dot = _ := _dot_aux.(seal_eq).

Global Instance _dot_persistent :
  Persistent o1 -> Persistent o2 -> Persistent (_dot o1 o2).
Proof. solve_Offset_persistent _dot_eq. Qed.

Definition _offsetL_def (o : Offset) (l : Loc) : Loc :=
  as_Loc (fun a => Exists a', o a' a ** l a').
Definition _offsetL_aux : seal (@_offsetL_def). by eexists. Qed.
Definition _offsetL := _offsetL_aux.(unseal).
Definition _offsetL_eq : @_offsetL = _ := _offsetL_aux.(seal_eq).

Global Instance _offsetL_persistent o l :
  Persistent o -> Persistent l -> Persistent (_offsetL o l).
Proof. solve_Loc_persistent _offsetL_eq. Qed.

Definition _offsetR_def (o : Offset) (r : Rep) : Rep :=
  as_Rep (fun a => Exists a', o a a' ** r a').
Definition _offsetR_aux : seal (@_offsetR_def). by eexists. Qed.
Definition _offsetR := _offsetR_aux.(unseal).
Definition _offsetR_eq : @_offsetR = _ := _offsetR_aux.(seal_eq).

Global Instance _offsetR_persistent o l :
  Persistent o -> Persistent l -> Persistent (_offsetR o l).
Proof. solve_Rep_persistent _offsetR_eq. Qed.

Definition addr_of_def (a : Rep) (b : val) : mpred := a b.
Definition addr_of_aux : seal (@addr_of_def). by eexists. Qed.
Definition addr_of := addr_of_aux.(unseal).
Definition addr_of_eq : @addr_of = _ := addr_of_aux.(seal_eq).
Arguments addr_of : simpl never.
Notation "a &~ b" := (addr_of a b) (at level 30, no associativity).

Global Instance addr_of_persistent : Persistent o -> Persistent (addr_of o l).
Proof. rewrite addr_of_eq. apply _. Qed.

Definition _at_def (base : Loc) (P : Rep) : mpred :=
  Exists a, base a ** P a.
Definition _at_aux : seal (@_at_def). by eexists. Qed.
Definition _at := _at_aux.(unseal).
Definition _at_eq : @_at = _ := _at_aux.(seal_eq).

Global Instance _at_persistent :
  Persistent base -> Persistent P -> Persistent (_at base P).
Proof. rewrite _at_eq. apply _. Qed.

(** Values
 * These `Rep` predicates wrap `ptsto` facts
 *)
(* Make Opauqe *)
Definition pureR (P : mpred) : Rep :=
  as_Rep (fun _ => P).

Global Instance pureR_persistent (P : mpred) :
  Persistent P -> Persistent (pureR P).
Proof. intros. apply monPred_at_persistent_inv. apply  _. Qed.

Definition tint_def (sz : size) q (v : Z) : Rep :=
  as_Rep (fun addr => tptsto (Tint sz Signed) q addr (Vint v) **
                             [| has_type (Vint v) (Tint sz Signed) |]).
Definition tint_aux : seal (@tint_def). by eexists. Qed.
Definition tint := tint_aux.(unseal).
Definition tint_eq : @tint = _ := tint_aux.(seal_eq).

Global Instance tint_timeless sz q v : Timeless (tint sz q v).
Proof. solve_Rep_timeless tint_eq. Qed.

Definition tuint_def (sz : size) q (v : Z) : Rep :=
  as_Rep (fun addr => tptsto (Tint sz Unsigned) q addr (Vint v) **
       [| has_type (Vint v) (Tint sz Unsigned) |]).
Definition tuint_aux : seal (@tuint_def). by eexists. Qed.
Definition tuint := tuint_aux.(unseal).
Definition tuint_eq : @tuint = _ := tuint_aux.(seal_eq).

Global Instance tuint_timeless sz q v : Timeless (tuint sz q v).
Proof. solve_Rep_timeless tuint_eq. Qed.

Definition tptr_def (ty : type) q (p : ptr) : Rep :=
  as_Rep (fun addr => tptsto (Tpointer ty) q addr (Vptr p)).
Definition tptr_aux : seal (@tptr_def). by eexists. Qed.
Definition tptr := tptr_aux.(unseal).
Definition tptr_eq : @tptr = _ := tptr_aux.(seal_eq).

Global Instance tptr_timeless ty q p : Timeless (tptr ty q p).
Proof. solve_Rep_timeless tptr_eq. Qed.

Definition tref_def (ty : type) (p : val) : Rep :=
  as_Rep (fun addr => [| addr = p |]).
Definition tref_aux : seal (@tref_def). by eexists. Qed.
Definition tref := tref_aux.(unseal).
Definition tref_eq : @tref = _ := tref_aux.(seal_eq).

Global Instance tref_timeless ty p : Timeless (tref ty p).
Proof. solve_Rep_timeless tref_eq. Qed.

Definition tprim_def (ty : type) q (v : val) : Rep :=
  as_Rep (fun addr => tptsto ty q addr v ** [| has_type v (drop_qualifiers ty) |]).
Definition tprim_aux : seal (@tprim_def). by eexists. Qed.
Definition tprim := tprim_aux.(unseal).
Definition tprim_eq : @tprim = _ := tprim_aux.(seal_eq).

Global Instance tprim_timeless ty q p : Timeless (tprim ty q p).
Proof. solve_Rep_timeless tprim_eq. Qed.

Definition uninit_def (ty : type) q : Rep :=
  as_Rep (fun addr => Exists bits,
       (* with_genv (fun env => [| size_of env ty size |]) ** *)
       (tprim ty q bits) addr ).
Definition uninit_aux : seal (@uninit_def). by eexists. Qed.
Definition uninit := uninit_aux.(unseal).
Definition uninit_eq : @uninit = _ := uninit_aux.(seal_eq).

Global Instance uninit_timeless ty q : Timeless (uninit ty q).
Proof. solve_Rep_timeless uninit_eq. Qed.

(* this should mean "anything, including uninitialized" *)
Definition tany_def (ty : type) q : Rep :=
  as_Rep (fun addr => (Exists v, (tprim ty q v) addr) \\//
       (uninit ty q) addr).
Definition tany_aux : seal (@tany_def). by eexists. Qed.
Definition tany := tany_aux.(unseal).
Definition tany_eq : @tany = _ := tany_aux.(seal_eq).

Global Instance tany_timeless ty q : Timeless (tany ty q).
Proof. solve_Rep_timeless tany_eq. Qed.

(* this isn't really necessary, we should simply drop it and write
 * predicates in this way to start with
 *)
Definition tinv_def {model} (Inv : val -> model -> mpred) (m : model) : Rep :=
  as_Rep (fun addr => Inv addr m).
Definition tinv_aux : seal (@tinv_def). by eexists. Qed.
Definition tinv := tinv_aux.(unseal).
Definition tinv_eq : @tinv = _ := tinv_aux.(seal_eq).

Definition is_null_def : Rep :=
  as_Rep (fun addr => [| addr = Vptr nullptr |]).
Definition is_null_aux : seal (@is_null_def). by eexists. Qed.
Definition is_null := is_null_aux.(unseal).
Definition is_null_eq : @is_null = _ := is_null_aux.(seal_eq).

Global Instance is_null_persistent : Persistent (is_null).
Proof. solve_Rep_persistent is_null_eq. Qed.

Definition is_nonnull_def : Rep :=
  as_Rep (fun addr => Exists p, [| p <> nullptr |] ** [| addr = Vptr p |]).
Definition is_nonnull_aux : seal (@is_nonnull_def). by eexists. Qed.
Definition is_nonnull := is_nonnull_aux.(unseal).
Definition is_nonnull_eq : @is_nonnull = _ := is_nonnull_aux.(seal_eq).

Global Instance is_nonnull_persistent : Persistent (is_nonnull).
Proof. solve_Rep_persistent is_nonnull_eq. Qed.

Definition tlocal_at_def (r : region) (l : ident) (a : val) (v : Rep) : mpred :=
  _local r l &~ a ** _at (_eq a) v.
Definition tlocal_at_aux : seal (@tlocal_at_def). by eexists. Qed.
Definition tlocal_at := tlocal_at_aux.(unseal).
Definition tlocal_at_eq : @tlocal_at = _ := tlocal_at_aux.(seal_eq).

Global Instance tlocal_at_persistent r l a v :
  Persistent v -> Persistent (tlocal_at r l a v).
Proof. rewrite tlocal_at_eq. apply _. Qed.

Definition tlocal_def (r : region) (x : ident) (v : Rep) : mpred :=
  Exists a, tlocal_at r x a v.
Definition tlocal_aux : seal (@tlocal_def). by eexists. Qed.
Definition tlocal := tlocal_aux.(unseal).
Definition tlocal_eq : @tlocal = _ := tlocal_aux.(seal_eq).

Global Instance tlocal_persistent r x v :
  Persistent v -> Persistent (tlocal r x v).
Proof. rewrite tlocal_eq. apply _. Qed.

(* this is for `Indirect` field references *)
Fixpoint path_to_Offset (from : globname) (final : ident)
         (ls : list (ident * globname))
: Offset :=
  match ls with
  | nil => _field {| f_type := from ; f_name := final |}
  | cons (i,c) ls =>
    _dot (_field {| f_type := from ; f_name := i |}) (path_to_Offset c final ls)
  end.

Definition offset_for (cls : globname) (f : FieldOrBase) : Offset :=
  match f with
  | Base parent => _super cls parent
  | Field i => _field {| f_type := cls ; f_name := i |}
  | Indirect ls final =>
    path_to_Offset cls final ls
  | This => _id
  end.

Global Opaque _local _global _at _sub _field _offsetR _offsetL _dot tprim tint tuint tptr is_null is_nonnull addr_of.

End with_Σ.

Arguments addr_of : simpl never.
Notation "a &~ b" := (addr_of a b) (at level 30, no associativity).
Coercion pureR : mpred >-> Rep.
