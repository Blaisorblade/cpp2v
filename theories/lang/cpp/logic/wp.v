(*
 * Copyright (c) 2020 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 *)
(**
 * Definitions for the semantics
 *)
Require Import bedrock.lang.prelude.base.
Require Import iris.bi.monpred.
Require Import iris.base_logic.lib.fancy_updates.
From iris.proofmode Require Import tactics classes.

From bedrock.lang.cpp Require Import
     ast semantics logic.pred.

Set Primitive Projections.

(* expression continuations
 * - in full C++, this includes exceptions, but our current semantics
 *   doesn't treat those.
 *)
Definition epred `{Σ : cpp_logic thread_info} := mpred.
Global Bind Scope bi_scope with epred.

Definition FreeTemps `{Σ : cpp_logic thread_info} := mpred.
Global Bind Scope bi_scope with FreeTemps.

(** Statements *)
(* continuations
  * C++ statements can terminate in 4 ways.
  *
  * note(gmm): technically, they can also raise exceptions; however,
  * our current semantics doesn't capture this. if we want to support
  * exceptions, we should be able to add another case,
  * `k_throw : val -> mpred`.
  *)
Record Kpreds `{Σ : cpp_logic thread_info} :=
  { k_normal   : mpred
  ; k_return   : option val -> FreeTemps -> mpred
  ; k_break    : mpred
  ; k_continue : mpred
  }.
Global Bind Scope bi_scope with Kpreds.

Section with_cpp.
  Context `{Σ : cpp_logic thread_info}.

  (* [SP] denotes the sequence point for an expression *)
  Definition SP (Q : val -> mpred) (v : val) (free : FreeTemps) : mpred :=
    free ** Q v.

  (* The expressions in the C++ language are categorized into five
   * "value categories" as defined in:
   *    http://eel.is/c++draft/expr.prop#basic.lval-1
   *
   * - "A glvalue is an expression whose evaluation determines the identity of
   *    an object or function."
   *   http://eel.is/c++draft/expr.prop#basic.lval-1.1
   * - "A prvalue is an expression whose evaluation initializes an object or
   *    computes the value of an operand of an operator, as specified by the
   *    context in which it appears, or an expression that has type cv void."
   *   http://eel.is/c++draft/expr.prop#basic.lval-1.2
   * - "An xvalue is a glvalue that denotes an object whose resources can be
   *    reused (usually because it is near the end of its lifetime)."
   *   http://eel.is/c++draft/expr.prop#basic.lval-1.3
   * - "An lvalue is a glvalue that is not an xvalue."
   *   http://eel.is/c++draft/expr.prop#basic.lval-1.4
   * - "An rvalue is a prvalue or an xvalue."
   *   http://eel.is/c++draft/expr.prop#basic.lval-1.5
   *)

  (** lvalues *)
  (* [wp_lval σ E ti ρ e Q] evaluates the expression [e] in region [ρ]
   * against thread id [ti] with mask [E] and continutation [Q].
   *)
  Parameter wp_lval
    : forall {resolve:genv}, coPset -> thread_info -> region ->
        Expr ->
        (ptr -> FreeTemps -> epred) -> (* result -> free -> post *)
        mpred. (* pre-condition *)

  Axiom wp_lval_shift : forall σ M ti ρ e Q,
      (|={M}=> wp_lval (resolve:=σ) M ti ρ e (fun v free => |={M}=> Q v free))
    ⊢ wp_lval (resolve:=σ) M ti ρ e Q.

  Axiom wp_lval_frame :
    forall σ1 σ2 M ti ρ e k1 k2,
      genv_leq σ1 σ2 ->
      Forall v f, k1 v f -* k2 v f |-- @wp_lval σ1 M ti ρ e k1 -* @wp_lval σ2 M ti ρ e k2.
  Global Instance Proper_wp_lval :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==>
            pointwise_relation _ (pointwise_relation _ lentails) ==> lentails)
           (@wp_lval).
  Proof.
    repeat red. intros; subst.
    iIntros "X". iRevert "X".
    iApply wp_lval_frame; eauto.
    iIntros (v). iIntros (f). iApply H4.
  Qed.

  Section wp_lval.
    Context {σ : genv} (M : coPset) (ti : thread_info) (ρ : region) (e : Expr).
    Local Notation WP := (wp_lval (resolve:=σ) M ti ρ e) (only parsing).
    Implicit Types P : mpred.
    Implicit Types Q : ptr → FreeTemps → epred.

    Lemma wp_lval_wand Q1 Q2 : WP Q1 |-- (∀ v f, Q1 v f -* Q2 v f) -* WP Q2.
    Proof. iIntros "Hwp HK". by iApply (wp_lval_frame with "HK Hwp"). Qed.
    Lemma fupd_wp_lval Q : (|={M}=> WP Q) |-- WP Q.
    Proof.
      rewrite -{2}wp_lval_shift. apply fupd_elim. rewrite -fupd_intro.
      iIntros "Hwp". iApply (wp_lval_wand with "Hwp"). auto.
    Qed.
    Lemma wp_lval_fupd Q : WP (λ v f, |={M}=> Q v f) |-- WP Q.
    Proof. iIntros "Hwp". by iApply (wp_lval_shift with "[$Hwp]"). Qed.

    (* proof mode *)
    Global Instance elim_modal_fupd_wp_lval p P Q :
      ElimModal True p false (|={M}=> P) P (WP Q) (WP Q).
    Proof.
      rewrite /ElimModal. rewrite bi.intuitionistically_if_elim/=.
      by rewrite fupd_frame_r bi.wand_elim_r fupd_wp_lval.
    Qed.
    Global Instance elim_modal_bupd_wp_lval p P Q :
      ElimModal True p false (|==> P) P (WP Q) (WP Q).
    Proof.
      rewrite /ElimModal (bupd_fupd M). exact: elim_modal_fupd_wp_lval.
    Qed.
    Global Instance add_modal_fupd_wp_lval P Q : AddModal (|={M}=> P) P (WP Q).
    Proof.
      rewrite/AddModal. by rewrite fupd_frame_r bi.wand_elim_r fupd_wp_lval.
    Qed.
  End wp_lval.

  (** prvalue *)
  (*
   * there are two distinct weakest pre-conditions for this corresponding to the
   * stndard text:
   * "A prvalue is an expression whose evaluation...
   * 1. initializes an object, or
   * 2. computes the value of an operand of an operator,
   * as specified by the context in which it appears,..."
   *)

  (* evaluate a prvalue that "initializes an object"
   *)
  Parameter wp_init
    : forall {resolve:genv}, coPset -> thread_info -> region ->
                        type -> ptr -> Expr ->
                        (FreeTemps -> epred) -> (* free -> post *)
                        mpred. (* pre-condition *)

  Axiom wp_init_shift : forall σ M ti ρ ty v e Q,
      (|={M}=> wp_init (resolve:=σ) M ti ρ ty v e (fun free => |={M}=> Q free))
    ⊢ wp_init (resolve:=σ) M ti ρ ty v e Q.

  Axiom wp_init_frame :
    forall σ1 σ2 M ti ρ t v e k1 k2,
      genv_leq σ1 σ2 ->
      Forall f, k1 f -* k2 f |-- @wp_init σ1 M ti ρ t v e k1 -* @wp_init σ2 M ti ρ t v e k2.

  Global Instance Proper_wp_init :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==> eq ==> eq ==>
            pointwise_relation _ lentails ==> lentails)
           (@wp_init).
  Proof.
    repeat red; intros; subst.
    iIntros "X"; iRevert "X"; iApply wp_init_frame; eauto.
    iIntros (f); iApply H6.
  Qed.

  Section wp_init.
    Context {σ : genv} (M : coPset) (ti : thread_info) (ρ : region)
      (t : type) (p : ptr) (e : Expr).
    Local Notation WP := (wp_init (resolve:=σ) M ti ρ t p e) (only parsing).
    Implicit Types P : mpred.
    Implicit Types Q : FreeTemps → epred.

    Lemma wp_init_wand Q1 Q2 : WP Q1 |-- (∀ f, Q1 f -* Q2 f) -* WP Q2.
    Proof. iIntros "Hwp HK". by iApply (wp_init_frame with "HK Hwp"). Qed.
    Lemma fupd_wp_init Q : (|={M}=> WP Q) |-- WP Q.
    Proof.
      rewrite -{2}wp_init_shift. apply fupd_elim. rewrite -fupd_intro.
      iIntros "Hwp". iApply (wp_init_wand with "Hwp"). auto.
    Qed.
    Lemma wp_init_fupd Q : WP (λ f, |={M}=> Q f) |-- WP Q.
    Proof. iIntros "Hwp". by iApply (wp_init_shift with "[$Hwp]"). Qed.

    (* proof mode *)
    Global Instance elim_modal_fupd_wp_init q P Q :
      ElimModal True q false (|={M}=> P) P (WP Q) (WP Q).
    Proof.
      rewrite /ElimModal. rewrite bi.intuitionistically_if_elim/=.
      by rewrite fupd_frame_r bi.wand_elim_r fupd_wp_init.
    Qed.
    Global Instance elim_modal_bupd_wp_init q P Q :
      ElimModal True q false (|==> P) P (WP Q) (WP Q).
    Proof.
      rewrite /ElimModal (bupd_fupd M). exact: elim_modal_fupd_wp_init.
    Qed.
    Global Instance add_modal_fupd_wp_init P Q : AddModal (|={M}=> P) P (WP Q).
    Proof.
      rewrite/AddModal. by rewrite fupd_frame_r bi.wand_elim_r fupd_wp_init.
    Qed.
  End wp_init.

  (* evaluate a prvalue that "computes the value of an operand of an operator"
   *)
  Parameter wp_prval
    : forall {resolve:genv}, coPset -> thread_info -> region ->
        Expr ->
        (val -> FreeTemps -> epred) -> (* result -> free -> post *)
        (* ^^ TODO the biggest question is what does this [val] represent
         *)
        mpred. (* pre-condition *)

  Axiom wp_prval_shift : forall σ M ti ρ e Q,
      (|={M}=> wp_prval (resolve:=σ) M ti ρ e (fun v free => |={M}=> Q v free))
    ⊢ wp_prval (resolve:=σ) M ti ρ e Q.

  Axiom wp_prval_frame :
    forall σ1 σ2 M ti ρ e k1 k2,
      genv_leq σ1 σ2 ->
      Forall v f, k1 v f -* k2 v f |-- @wp_prval σ1 M ti ρ e k1 -* @wp_prval σ2 M ti ρ e k2.
  Global Instance Proper_wp_prval :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==>
            pointwise_relation _ (pointwise_relation _ lentails) ==> lentails)
           (@wp_prval).
  Proof. repeat red; intros; subst.
         iIntros "X"; iRevert "X".
         iApply wp_prval_frame; eauto.
         iIntros (v); iIntros (f); iApply H4.
  Qed.

  Section wp_prval.
    Context {σ : genv} (M : coPset) (ti : thread_info) (ρ : region) (e : Expr).
    Local Notation WP := (wp_prval (resolve:=σ) M ti ρ e) (only parsing).
    Implicit Types P : mpred.
    Implicit Types Q : val → FreeTemps → epred.

    Lemma wp_prval_wand Q1 Q2 : WP Q1 |-- (∀ v f, Q1 v f -* Q2 v f) -* WP Q2.
    Proof. iIntros "Hwp HK". by iApply (wp_prval_frame with "HK Hwp"). Qed.
    Lemma fupd_wp_prval Q : (|={M}=> WP Q) |-- WP Q.
    Proof.
      rewrite -{2}wp_prval_shift. apply fupd_elim. rewrite -fupd_intro.
      iIntros "Hwp". iApply (wp_prval_wand with "Hwp"). auto.
    Qed.
    Lemma wp_prval_fupd Q : WP (λ v f, |={M}=> Q v f) |-- WP Q.
    Proof. iIntros "Hwp". by iApply (wp_prval_shift with "[$Hwp]"). Qed.

    (* proof mode *)
    Global Instance elim_modal_fupd_wp_prval p P Q :
      ElimModal True p false (|={M}=> P) P (WP Q) (WP Q).
    Proof.
      rewrite /ElimModal. rewrite bi.intuitionistically_if_elim/=.
      by rewrite fupd_frame_r bi.wand_elim_r fupd_wp_prval.
    Qed.
    Global Instance elim_modal_bupd_wp_prval p P Q :
      ElimModal True p false (|==> P) P (WP Q) (WP Q).
    Proof.
      rewrite /ElimModal (bupd_fupd M). exact: elim_modal_fupd_wp_prval.
    Qed.
    Global Instance add_modal_fupd_wp_prval P Q : AddModal (|={M}=> P) P (WP Q).
    Proof.
      rewrite/AddModal. by rewrite fupd_frame_r bi.wand_elim_r fupd_wp_prval.
    Qed.
  End wp_prval.

  (** xvalues *)

  (* evaluate an expression as an xvalue *)
  Parameter wp_xval
    : forall {resolve:genv}, coPset -> thread_info -> region ->
                        Expr ->
                        (ptr -> FreeTemps -> epred) -> (* result -> free -> post *)
                        mpred. (* pre-condition *)

  Axiom wp_xval_shift : forall σ M ti ρ e Q,
      (|={M}=> wp_xval (resolve:=σ) M ti ρ e (fun v free => |={M}=> Q v free))
    ⊢ wp_xval (resolve:=σ) M ti ρ e Q.

  Axiom wp_xval_frame :
    forall σ1 σ2 M ti ρ e k1 k2,
      genv_leq σ1 σ2 ->
      Forall v f, k1 v f -* k2 v f |-- @wp_xval σ1 M ti ρ e k1 -* @wp_xval σ2 M ti ρ e k2.
  Global Instance Proper_wp_xval :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==>
            pointwise_relation _ (pointwise_relation _ lentails) ==> lentails)
           (@wp_xval).
  Proof. repeat red; intros; subst.
         iIntros "X"; iRevert "X".
         iApply wp_xval_frame; eauto.
         iIntros (v); iIntros (f); iApply H4.
  Qed.

  Section wp_xval.
    Context {σ : genv} (M : coPset) (ti : thread_info) (ρ : region) (e : Expr).
    Local Notation WP := (wp_xval (resolve:=σ) M ti ρ e) (only parsing).
    Implicit Types P : mpred.
    Implicit Types Q : ptr → FreeTemps → epred.

    Lemma wp_xval_wand Q1 Q2 : WP Q1 |-- (∀ v f, Q1 v f -* Q2 v f) -* WP Q2.
    Proof. iIntros "Hwp HK". by iApply (wp_xval_frame with "HK Hwp"). Qed.
    Lemma fupd_wp_xval Q : (|={M}=> WP Q) |-- WP Q.
    Proof.
      rewrite -{2}wp_xval_shift. apply fupd_elim. rewrite -fupd_intro.
      iIntros "Hwp". iApply (wp_xval_wand with "Hwp"). auto.
    Qed.
    Lemma wp_xval_fupd Q : WP (λ v f, |={M}=> Q v f) |-- WP Q.
    Proof. iIntros "Hwp". by iApply (wp_xval_shift with "[$Hwp]"). Qed.

    (* proof mode *)
    Global Instance elim_modal_fupd_wp_xval p P Q :
      ElimModal True p false (|={M}=> P) P (WP Q) (WP Q).
    Proof.
      rewrite /ElimModal. rewrite bi.intuitionistically_if_elim/=.
      by rewrite fupd_frame_r bi.wand_elim_r fupd_wp_xval.
    Qed.
    Global Instance elim_modal_bupd_wp_xval p P Q :
      ElimModal True p false (|==> P) P (WP Q) (WP Q).
    Proof.
      rewrite /ElimModal (bupd_fupd M). exact: elim_modal_fupd_wp_xval.
    Qed.
    Global Instance add_modal_fupd_wp_xval P Q : AddModal (|={M}=> P) P (WP Q).
    Proof.
      rewrite/AddModal. by rewrite fupd_frame_r bi.wand_elim_r fupd_wp_xval.
    Qed.
  End wp_xval.

  (* Opaque wrapper of [False]: this represents a [False] obtained by a [ValCat] mismatch in [wp_glval]. *)
  Definition wp_glval_mismatch {resolve : genv} (M : coPset) (ti : thread_info) (r : region) (vc : ValCat) (e : Expr) : (ptr -> FreeTemps -> mpred) -> mpred := funI _ => False.
  Global Arguments wp_glval_mismatch : simpl never.

  (* evaluate an expression as a generalized lvalue *)

  (* in some cases we need to evaluate a glvalue but we know the
     the underlying primitive value category. This makes some weakest
     pre-condition axioms a bit shorter
   *)
  Definition wp_glval {resolve} M ti r (vc : ValCat) (e : Expr) : (ptr -> FreeTemps -> mpred) -> mpred :=
      match vc with
      | Lvalue => wp_lval (resolve:=resolve) M ti r e
      | Xvalue => wp_xval (resolve:=resolve) M ti r e
      | _ => wp_glval_mismatch M ti r vc e
      end%I.

  (** Bundled evaluation, this enables us slightly more concisely
      represent some weakest-precondition rules.
   *)
  Section wpe.
    Context {resolve:genv}.
    Variable (M : coPset) (ti : thread_info) (ρ : region).

    Definition wpe (vc : ValCat) (e : Expr) (Q :val -> FreeTemps -> mpred) : mpred :=
      match vc with
      | Lvalue => @wp_lval resolve M ti ρ e (fun p => Q (Vptr p))
      | Prvalue => @wp_prval resolve M ti ρ e Q
      | Xvalue => @wp_xval resolve M ti ρ e (fun p => Q (Vptr p))
      end.

    Definition wpAny (vce : ValCat * Expr)
      : (val -> FreeTemps -> mpred) -> mpred :=
      let '(vc,e) := vce in
      wpe vc e.

    Definition wpAnys := fun ve Q free => wpAny ve (fun v f => Q v (f ** free)).
  End wpe.

  Lemma wpe_frame σ1 σ2 M ti ρ vc e k1 k2:
    genv_leq σ1 σ2 ->
    Forall v f, k1 v f -* k2 v f |-- wpe (resolve := σ1) M ti ρ vc e k1 -* wpe (resolve:=σ2) M ti ρ vc e k2.
  Proof.
    destruct vc => /=; [ | apply wp_prval_frame | ].
    - intros. rewrite -wp_lval_frame; eauto.
      iIntros "h" (v f) "x"; iApply "h"; iFrame.
    - intros. rewrite -wp_xval_frame; eauto.
      iIntros "h" (v f) "x"; iApply "h"; iFrame.
  Qed.

  Global Instance Proper_wpe :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==> eq ==> (eq ==> lentails ==> lentails) ==> lentails)
           (@wpe).
  Proof.
    repeat red; intros; subst.
    iIntros "X"; iRevert "X"; iApply wpe_frame; eauto.
    iIntros (v f); iApply H5; reflexivity.
  Qed.

  Global Instance Proper_wpe' :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==> eq ==> (pointwise_relation _ (pointwise_relation _ lentails)) ==> lentails)
           (@wpe).
  Proof.
    repeat red; intros; subst.
    iIntros "X"; iRevert "X"; iApply wpe_frame; eauto.
    iIntros (v f); iApply H5; reflexivity.
  Qed.

  Lemma wpAny_frame σ1 σ2 M ti ρ e k1 k2:
    genv_leq σ1 σ2 ->
    Forall v f, k1 v f -* k2 v f |-- wpAny (resolve := σ1) M ti ρ e k1 -* wpAny (resolve:=σ2) M ti ρ e k2.
  Proof. destruct e; apply: wpe_frame. Qed.

  Global Instance Proper_wpAny :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==> (eq ==> lentails ==> lentails) ==> lentails)
           (@wpAny).
  Proof.
    repeat red; intros; subst.
    iIntros "X"; iRevert "X"; iApply wpAny_frame; eauto.
    iIntros (v f); iApply H4; reflexivity.
  Qed.

  Global Instance Proper_wpAny' :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==> (pointwise_relation _ (pointwise_relation _ lentails)) ==> lentails)
           (@wpAny).
  Proof.
    repeat red; intros; subst.
    iIntros "X"; iRevert "X"; iApply wpAny_frame; eauto.
    iIntros (v f); iApply H4; reflexivity.
  Qed.

  (** initializers *)
  (* TODO this seems unnecessary *)
  Parameter wpi
    : forall {resolve:genv} (M : coPset) (ti : thread_info) (ρ : region)
        (cls : globname) (this : ptr) (init : Initializer)
        (Q : mpred -> mpred), mpred.

  Axiom wpi_shift : forall σ M ti ρ cls this e Q,
      (|={M}=> wpi (resolve:=σ) M ti ρ cls this e (fun k => |={M}=> Q k))
    ⊢ wpi (resolve:=σ) M ti ρ cls this e Q.

  Axiom wpi_frame :
    forall σ1 σ2 M ti ρ cls this e k1 k2,
      genv_leq σ1 σ2 ->
      Forall f, k1 f -* k2 f |-- @wpi σ1 M ti ρ cls this e k1 -* @wpi σ2 M ti ρ cls this e k2.

  Global Instance Proper_wpi :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==> eq ==> eq ==> (lentails ==> lentails) ==> lentails)
           (@wpi).
  Proof. repeat red; intros; subst.
         iIntros "X"; iRevert "X"; iApply wpi_frame; eauto.
         iIntros (f); iApply H6. reflexivity.
  Qed.

  Section wpi.
    Context {σ : genv} (M : coPset) (ti : thread_info) (ρ : region)
      (cls : globname) (this : ptr) (init : Initializer).
    Local Notation WP := (wpi (resolve:=σ) M ti ρ cls this init) (only parsing).
    Implicit Types P : mpred.
    Implicit Types k : mpred → mpred.

    Lemma wpi_wand k1 k2 : WP k1 |-- (∀ Q, k1 Q -* k2 Q) -* WP k2.
    Proof. iIntros "Hwp HK". by iApply (wpi_frame with "HK Hwp"). Qed.
    Lemma fupd_wpi k : (|={M}=> WP k) |-- WP k.
    Proof.
      rewrite -{2}wpi_shift. apply fupd_elim. rewrite -fupd_intro.
      iIntros "Hwp". iApply (wpi_wand with "Hwp"). auto.
    Qed.
    Lemma wpi_fupd k : WP (λ Q, |={M}=> k Q) |-- WP k.
    Proof. iIntros "Hwp". by iApply (wpi_shift with "[$Hwp]"). Qed.

    (* proof mode *)
    Global Instance elim_modal_fupd_wpi p P k :
      ElimModal True p false (|={M}=> P) P (WP k) (WP k).
    Proof.
      rewrite /ElimModal. rewrite bi.intuitionistically_if_elim/=.
      by rewrite fupd_frame_r bi.wand_elim_r fupd_wpi.
    Qed.
    Global Instance elim_modal_bupd_wpi p P k :
      ElimModal True p false (|==> P) P (WP k) (WP k).
    Proof.
      rewrite /ElimModal (bupd_fupd M). exact: elim_modal_fupd_wpi.
    Qed.
    Global Instance add_modal_fupd_wpi P k : AddModal (|={M}=> P) P (WP k).
    Proof.
      rewrite/AddModal. by rewrite fupd_frame_r bi.wand_elim_r fupd_wpi.
    Qed.
  End wpi.

  (** destructors *)
  Parameter wpd
    : forall {resolve:genv} (M : coPset) (ti : thread_info) (ρ : region)
        (cls : globname) (this : ptr)
        (init : FieldOrBase * obj_name)
        (Q : epred), mpred.

  Axiom wpd_shift : forall σ M ti ρ cls this e Q,
      (|={M}=> wpd (resolve:=σ) M ti ρ cls this e (|={M}=> Q))
    ⊢ wpd (resolve:=σ) M ti ρ cls this e Q.

  Axiom wpd_frame :
    forall σ1 σ2 M ti ρ cls this e k1 k2,
      genv_leq σ1 σ2 ->
      k1 -* k2 |-- @wpd σ1 M ti ρ cls this e k1 -* @wpd σ2 M ti ρ cls this e k2.

  Global Instance Proper_wpd :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==> eq ==> eq ==> lentails ==> lentails)
           (@wpd).
  Proof. repeat red; intros; subst.
         iIntros "X"; iRevert "X"; iApply wpd_frame; eauto.
         iApply H6.
  Qed.

  Section wpd.
    Context {σ : genv} (M : coPset) (ti : thread_info) (ρ : region)
      (cls : globname) (this : ptr) (init : FieldOrBase * obj_name).
    Local Notation WP := (wpd (resolve:=σ) M ti ρ cls this init) (only parsing).
    Implicit Types P : mpred.
    Implicit Types k : mpred.

    Lemma wpd_wand k1 k2 : WP k1 |-- (k1 -* k2) -* WP k2.
    Proof. iIntros "Hwp HK". by iApply (wpd_frame with "HK Hwp"). Qed.
    Lemma fupd_wpd k : (|={M}=> WP k) |-- WP k.
    Proof.
      rewrite -{2}wpd_shift. apply fupd_elim. rewrite -fupd_intro.
      iIntros "Hwp". iApply (wpd_wand with "Hwp"). auto.
    Qed.
    Lemma wpd_fupd k : WP (|={M}=> k) |-- WP k.
    Proof. iIntros "Hwp". by iApply (wpd_shift with "[$Hwp]"). Qed.

    (* proof mode *)
    Global Instance elim_modal_fupd_wpd p P k :
      ElimModal True p false (|={M}=> P) P (WP k) (WP k).
    Proof.
      rewrite /ElimModal. rewrite bi.intuitionistically_if_elim/=.
      by rewrite fupd_frame_r bi.wand_elim_r fupd_wpd.
    Qed.
    Global Instance elim_modal_bupd_wpd p P k :
      ElimModal True p false (|==> P) P (WP k) (WP k).
    Proof.
      rewrite /ElimModal (bupd_fupd M). exact: elim_modal_fupd_wpd.
    Qed.
    Global Instance add_modal_fupd_wpd P k : AddModal (|={M}=> P) P (WP k).
    Proof.
      rewrite/AddModal. by rewrite fupd_frame_r bi.wand_elim_r fupd_wpd.
    Qed.
  End wpd.

  (** Statements *)

  Instance Kpreds_fupd: FUpd Kpreds :=
    funI l r Q =>
      {| k_normal := |={l,r}=> Q.(k_normal)
       ; k_return v f := |={l,r}=> Q.(k_return) v f
       ; k_break := |={l,r}=> Q.(k_break)
       ; k_continue := |={l,r}=> Q.(k_continue) |}.

  Definition void_return (P : mpred) : Kpreds :=
    {| k_normal := P
     ; k_return := funI r free => match r with
                              | None => free ** P
                              | Some _ => False
                              end
     ; k_break := False
     ; k_continue := False
    |}.

  Definition val_return (P : val -> mpred) : Kpreds :=
    {| k_normal := False
     ; k_return := funI r free => match r with
                              | None => False
                              | Some v => free ** P v
                              end
     ; k_break := False
     ; k_continue := False |}.

  Definition Kseq (Q : Kpreds -> mpred) (k : Kpreds) : Kpreds :=
    {| k_normal   := Q k
     ; k_return   := k.(k_return)
     ; k_break    := k.(k_break)
     ; k_continue := k.(k_continue) |}.

  (* loop with invariant `I` *)
  Definition Kloop (I : mpred) (Q : Kpreds) : Kpreds :=
    {| k_break    := Q.(k_normal)
     ; k_continue := I
     ; k_return   := Q.(k_return)
     ; k_normal   := Q.(k_normal) |}.

  Definition Kat_exit (Q : mpred -> mpred) (k : Kpreds) : Kpreds :=
    {| k_normal   := Q k.(k_normal)
     ; k_return v free := Q (k.(k_return) v free)
     ; k_break    := Q k.(k_break)
     ; k_continue := Q k.(k_continue) |}.

  Definition Kfree (a : mpred) : Kpreds -> Kpreds :=
    Kat_exit (fun P => a ** P).

  Definition Kpred_entails (k1 k2 : Kpreds) : Prop :=
      k1.(k_normal) |-- k2.(k_normal) ∧
      (∀ v free, k1.(k_return) v free |-- k2.(k_return) v free) ∧
      k1.(k_break) |-- k2.(k_break) ∧
      k1.(k_continue) |-- k2.(k_continue).

  Global Instance Kpreds_equiv : Equiv Kpreds :=
    fun (k1 k2 : Kpreds) =>
      k1.(k_normal) ≡ k2.(k_normal) ∧
      (∀ v free, k1.(k_return) v free ≡ k2.(k_return) v free) ∧
      k1.(k_break) ≡ k2.(k_break) ∧
      k1.(k_continue) ≡ k2.(k_continue).

  Lemma Kfree_Kfree : forall k P Q, Kfree P (Kfree Q k) ≡ Kfree (P ** Q) k.
  Proof using .
    split; [ | split; [ | split ] ]; simpl; intros;
      eapply bi.equiv_spec; split;
        try solve [ rewrite bi.sep_assoc; eauto ].
  Qed.

  Lemma Kfree_emp : forall k, Kfree emp k ≡ k.
  Proof using .
    split; [ | split; [ | split ] ]; simpl; intros;
      eapply bi.equiv_spec; split;
        try solve [ rewrite bi.emp_sep; eauto ].
  Qed.

  (* evaluate a statement *)
  Parameter wp
    : forall {resolve:genv}, coPset -> thread_info -> region -> Stmt -> Kpreds -> mpred.

  Axiom wp_shift : forall σ M ti ρ s Q,
      (|={M}=> wp (resolve:=σ) M ti ρ s (|={M}=> Q))
    ⊢ wp (resolve:=σ) M ti ρ s Q.

  Axiom wp_frame :
    forall σ1 σ2 M ti ρ s k1 k2,
      genv_leq σ1 σ2 ->
      (k1.(k_normal) -* k2.(k_normal)) //\\
      (Forall v f, k1.(k_return) v f -* k2.(k_return) v f) //\\
      (k1.(k_break) -* k2.(k_break)) //\\
      (k1.(k_continue) -* k2.(k_continue))
      |-- @wp σ1 M ti ρ s k1 -* @wp σ2 M ti ρ s k2.

  Global Instance Proper_wp :
    Proper (genv_leq ==> eq ==> eq ==> eq ==> eq ==> Kpred_entails ==> lentails)
           (@wp).
  Proof. repeat red; intros; subst.
         iIntros "X"; iRevert "X"; iApply wp_frame; eauto.
         destruct H4 as [ ? [ ? [ ? ? ] ] ].
         iSplit; [ iApply H0 | iSplit; [ | iSplit; [ iApply H2 | iApply H3 ] ] ].
         iIntros. iApply H1; eauto.
  Qed.

  Section wp.
    Context {σ : genv} (M : coPset) (ti : thread_info) (ρ : region) (s : Stmt).
    Local Notation WP := (wp (resolve:=σ) M ti ρ s) (only parsing).
    Implicit Types P : mpred.
    Implicit Types Q : Kpreds.

    Lemma wp_wand k1 k2 :
      WP k1 |--
      (* PDS: This conjunction shows up in several places and may
      deserve a definition and some supporting lemmas. *)
      ((k_normal k1 -* k_normal k2) ∧
      (∀ mv f, k_return k1 mv f -* k_return k2 mv f) ∧
      (k_break k1 -* k_break k2) ∧
      (k_continue k1 -* k_continue k2)) -*
      WP k2.
    Proof.
      iIntros "Hwp Hk". by iApply (wp_frame σ _ _ _ _ _ k1 with "[$Hk] Hwp").
    Qed.
    Lemma fupd_wp k : (|={M}=> WP k) |-- WP k.
    Proof.
      rewrite -{2}wp_shift. apply fupd_elim. rewrite -fupd_intro.
      iIntros "Hwp". iApply (wp_wand with "Hwp"). auto.
    Qed.
    Lemma wp_fupd k : WP (|={M}=> k) |-- WP k.
    Proof. iIntros "Hwp". by iApply (wp_shift with "[$Hwp]"). Qed.

    (* proof mode *)
    Global Instance elim_modal_fupd_wp p P k :
      ElimModal True p false (|={M}=> P) P (WP k) (WP k).
    Proof.
      rewrite /ElimModal. rewrite bi.intuitionistically_if_elim/=.
      by rewrite fupd_frame_r bi.wand_elim_r fupd_wp.
    Qed.
    Global Instance elim_modal_bupd_wp p P k :
      ElimModal True p false (|==> P) P (WP k) (WP k).
    Proof.
      rewrite /ElimModal (bupd_fupd M). exact: elim_modal_fupd_wp.
    Qed.
    Global Instance add_modal_fupd_wp P k : AddModal (|={M}=> P) P (WP k).
    Proof.
      rewrite/AddModal. by rewrite fupd_frame_r bi.wand_elim_r fupd_wp.
    Qed.
  End wp.

  (* this is the specification of assembly code
   *
   * [addr] represents the address of the entry point of the code.
   * note: the [list val] will be related to the register set.
   *)
  Parameter fspec
    : forall (tt : type_table) (fun_type : type) (ti : thread_info)
             (addr : val) (ls : list val) (Q : val -> epred), mpred.

  Axiom fspec_complete_type : forall te ft ti a ls Q,
      fspec te ft ti a ls Q
      |-- fspec te ft ti a ls Q **
          [| exists cc tret targs, ft = Tfunction (cc:=cc) tret targs |].

  (* this axiom states that the type environment for an [fspec] can be
     narrowed as long as the new type environment [small]/[tt2] is smaller than
     the old type environment ([big]/[tt1]), and [ft]
     is still a *complete type* in the new type environment [small]/[tt2].

     NOTE: This is informally justified by the fact that (in the absence
     of ODR) the implementation of the function is encapsulated and only
     the public interface (the type) is need to know how to call the function.
   *)
  Axiom fspec_strengthen : forall tt1 tt2 ft ti a ls Q,
      complete_type tt2.(globals) ft ->
      (* TODO(PG): even if [ft] is complete, the argument/return types might not be
      complete. That would make a call impossible, but does might not be
      enough to justify [fspec_strengthen] locally (tho I expect it suffices globally). *)
      sub_module tt2 tt1 ->
      fspec tt1.(globals) ft ti a ls Q |-- fspec tt2.(globals) ft ti a ls Q.

  (* this axiom is the standard rule of consequence for weakest
     pre-condition.
   *)
  Axiom fspec_frame : forall tt ft a ls ti Q1 Q2,
      Forall v, Q1 v -* Q2 v |-- @fspec tt ft ti a ls Q1 -* @fspec tt ft ti a ls Q2.

  Global Instance Proper_fspec : forall tt ft a ls ti,
      Proper (pointwise_relation _ lentails ==> lentails) (@fspec tt ft ti a ls).
  Proof. repeat red; intros.
         rewrite fspec_complete_type.
         iIntros "[X %]"; iRevert "X"; iApply fspec_frame; auto.
         iIntros (v); iApply H.
  Qed.

  Section fspec.
    Context {tt : type_table} {tf : type} (ti : thread_info) (addr : val) (ls : list val).
    Local Notation WP := (fspec tt tf ti addr ls) (only parsing).
    Implicit Types Q : val → epred.

    Lemma fspec_wand Q1 Q2 : WP Q1 |-- (∀ v, Q1 v -* Q2 v) -* WP Q2.
    Proof. iIntros "Hwp HK".
           iDestruct (fspec_complete_type with "Hwp") as "[Hwp %]".
           iApply (fspec_frame with "HK Hwp").
    Qed.
  End fspec.

  (* [Tmember_func ty fty] constructs the function type for a
     member function that takes a [this] parameter of [ty]
   *)
  Definition Tmember_func (ty : type) (fty : type) : type :=
    match fty with
    | @Tfunction cc ret args => Tfunction (cc:=cc) ret (Qconst (Tptr ty) :: args)
    | _ => fty
    end.

  (** [mspec tt this_ty fty ..] is the analogue of [fspec] for member functions.

      NOTE this includes constructors and destructors.

      NOTE the current implementation desugars this to [fspec] but this is not
           accurate according to the standard because a member function can not
           be casted to a regular function that takes an extra parameter.
   *)
  Definition mspec (tt : type_table) (this_type : type) (fun_type : type)
    : thread_info -> val -> list val -> (val -> epred) -> mpred :=
    fspec tt (Tmember_func this_type fun_type).

End with_cpp.

Export stdpp.coPset.
