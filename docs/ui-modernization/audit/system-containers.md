# Audit: Dialogs, Panels, Menus, Popovers

Baseline inventory for the visual/interaction modernization phase. Everything below is read
from the files as they exist today; every claim carries a `file:line`. No redesign is proposed.

Scope: `components-next/dialog`, `components-next/side-panel`, `components-next/dropdown-menu`,
`components-next/popover`, `components-next/selectmenu`, `components-next/TeleportWithDirection.vue`,
`components/Modal.vue` + its wrappers, plus every ad-hoc overlay found in the dashboard tree.

All paths are relative to `/home/user/lynomiachat/app/javascript/`.

---

## 1. Executive summary of what exists

| Family | Component | Mount points | Overlay mechanism |
| --- | --- | --- | --- |
| Modal (current) | `dashboard/components-next/dialog/Dialog.vue` | 63 (in 60 files) | native `<dialog>` + `showModal()` |
| Modal (legacy) | `dashboard/components/Modal.vue` (global `<woot-modal>`) | 29 (27 `<woot-modal>` tags + 2 direct `<Modal>`) + 3 wrapper components | `position: fixed` div, **no Teleport** |
| Side drawer | `dashboard/components-next/side-panel/SidePanel.vue` | 8 | Teleport + `fixed inset-y-3 end-3` |
| Anchored panel | `dashboard/components-next/popover/Popover.vue` | 8 | Teleport + measured `fixed` |
| Menu (data-driven) | `dashboard/components-next/dropdown-menu/DropdownMenu.vue` | 41 files | bare `absolute` div — **positioned by the consumer** |
| Menu (primitives) | `dashboard/components-next/dropdown-menu/base/*` | 10 files | `absolute`, or Teleport when opted in |
| Menu (legacy) | `dashboard/components-next/selectmenu/SelectMenu.vue` | 3 | `absolute`, `v-on-clickaway` |
| Context menu | `dashboard/components/ui/ContextMenu.vue` | Teleport + measured `fixed` |
| RTL shim | `dashboard/components-next/TeleportWithDirection.vue` | 10 | wraps `<Teleport>` in a `[dir]` div |

There are **four unrelated overlay engines** (native `<dialog>`, fixed-div modal, transitioned
Teleport drawer, measured-fixed popover) and **three unrelated outside-click mechanisms**
(`OnClickOutside` component, `vOnClickOutside` directive, `v-on-clickaway` legacy directive).

**There is no sheet or bottom-drawer component anywhere.** A search for `bottomsheet`,
`bottom-sheet`, and the bare token `sheet` across `dashboard/` and `shared/` returns zero
component hits, and no overlay uses `translate-y-full` or `fixed inset-x-0 bottom-0`. The only
mobile adaptation in the entire container system is `Popover.vue`'s below-`md` switch to a
top-anchored centered modal (`popover/Popover.vue:40-43,141-161`).

---

## 2. `components-next/dialog/Dialog.vue` — the current modal

### 2.1 Props

| Prop | Type | Default | Validator | Line |
| --- | --- | --- | --- | --- |
| `type` | String | `'edit'` | `['alert','edit']` | `dialog/Dialog.vue:10-14` |
| `title` | String | `''` | — | `:15-18` |
| `description` | String | `''` | — | `:19-22` |
| `cancelButtonLabel` | String | `''` | falls back to `DIALOG.BUTTONS.CANCEL` | `:23-26`, `:157` |
| `confirmButtonLabel` | String | `''` | falls back to `DIALOG.BUTTONS.CONFIRM` | `:27-30`, `:165` |
| `disableConfirmButton` | Boolean | `false` | — | `:31-34` |
| `isLoading` | Boolean | `false` | — | `:35-38` |
| `showCancelButton` | Boolean | `true` | — | `:39-42` |
| `showConfirmButton` | Boolean | `true` | — | `:43-46` |
| `overflowYAuto` | Boolean | `false` | — | `:47-50` |
| `width` | String | `'lg'` | `['3xl','2xl','xl','lg','md','sm']` | `:51-55` |
| `position` | String | `'center'` | `['center','top']` | `:56-60` |

Emits `confirm`, `close` (`:63`). Exposes `open()`, `close()` (`:114`) — it is **ref-driven**, not
`v-model`-driven, so every one of the 63 call sites holds a template ref and calls
`dialogRef.value.open()`.

`type` only changes the confirm button colour: `blue` for `edit`, `ruby` for `alert` (`:164`).

### 2.2 Widths

`maxWidthClass` maps the prop to a Tailwind `max-w-*` on the `<dialog>` (`:71-82`), with a
fallback to `max-w-md` for an unknown value. The element itself is `w-full` (`:121`).

| `width` | Class | px | Dialog mount points using it |
| --- | --- | --- | --- |
| `sm` | `max-w-sm` | 384 | **0** — declared but never used |
| `md` | `max-w-md` | 448 | 8 |
| `lg` (default) | `max-w-lg` | 512 | 47 (45 by default, 2 explicit) |
| `xl` | `max-w-xl` | 576 | 1 (dynamic, see below) |
| `2xl` | `max-w-2xl` | 672 | 3 |
| `3xl` | `max-w-3xl` | 768 | 4 |

### 2.3 Footer and button placement

The default footer (`:148-172`) is a single row: `flex items-center justify-between w-full gap-3`
with two `class="w-full"` buttons, so Cancel and Confirm each take ~50% and sit side by side.
Cancel is `variant="faded" color="slate"` `type="button"` (`:153-161`); Confirm is `type="submit"`
coloured by `type` (`:162-170`). The whole body is a `<form @submit.prevent="confirm">` (`:130-134`),
so Enter in any field fires `confirm`.

The row renders only if `showCancelButton || showConfirmButton` (`:150`). **There is no close (X)
affordance anywhere in `Dialog.vue`** — with `:show-cancel-button="false"` the only exits are
Escape and click-outside.

12 call sites replace the footer entirely via the `#footer` slot, each with its own layout:

| File | Line |
| --- | --- |
| `dashboard/components-next/Companies/CompanyCreateDialog.vue` | 59 |
| `dashboard/components-next/Contacts/ContactsForm/CreateNewContactDialog.vue` | 43 |
| `dashboard/components-next/captain/pageComponents/assistant/CreateAssistantDialog.vue` | 78 |
| `dashboard/components-next/captain/pageComponents/customTool/CreateCustomToolDialog.vue` | 70 |
| `dashboard/components-next/captain/pageComponents/document/CreateDocumentDialog.vue` | 51 |
| `dashboard/components-next/captain/pageComponents/inbox/ConnectInboxDialog.vue` | 48 |
| `dashboard/components-next/captain/pageComponents/response/CreateResponseDialog.vue` | 75 |
| `dashboard/components-next/captain/pageComponents/response/FaqSuggestionReviewDialog.vue` | 129 |
| `dashboard/components-next/recipes/RecipeDialog.vue` | 110 |
| `dashboard/components/widgets/conversation/commerce/CommerceOrderActions.vue` | 329 |
| `dashboard/routes/dashboard/settings/billing/components/PurchaseCreditsModal.vue` | 145 |
| `dashboard/routes/dashboard/settings/inbox/components/WhatsappManualMigrationDialog.vue` | 226 |

There is also a `#description` slot (`:140-144`) that replaces the `<p>` under the title.

### 2.4 Focus trap, Escape, click-outside

| Behaviour | Implementation | Line |
| --- | --- | --- |
| Focus trap | **Native** — `showModal()` puts the dialog in the top layer and makes the rest of the document inert | `:90` |
| Initial focus | Browser default (first focusable descendant). No `autofocus`, no explicit focus call | — |
| Focus restore | Browser default. No `previousActiveElement` bookkeeping | — |
| Escape | **Native** `cancel`→`close`; handled by `@close.prevent="handleDialogClose"` | `:127`, `:101` |
| Stacked Escape | `handleDialogClose` ignores the event unless `e.target === dialogRef.value`, so a child `<dialog>` (ProseMirror link prompt) closing does not bubble up and close the parent | `:99-101` |
| Click-outside | `OnClickOutside` from `@vueuse/components` wraps the inner form | `:129` |
| Stacked click-outside | `handleClickOutside` queries `document.querySelectorAll('dialog[open]')` and acts only if this dialog is the **last** one in the list | `:103-108` |
| Inner click guard | `@click.stop` on the form | `:134` |
| Backdrop | `dialog::backdrop { @apply bg-n-alpha-black1 backdrop-blur-[4px] }` — scoped CSS, the one place in the file that is not Tailwind-in-template | `:180-182` |

Slot content is gated on `isOpen` (`:146`), so a dialog's body is not mounted until it is opened
and is unmounted on close — state inside is discarded every time.

### 2.5 Scroll behaviour

`overflowYAuto` toggles `overflow-y-auto` vs `overflow-visible` on the `<dialog>` (`:125`). The
inner form is **always** `overflow-visible` (`:132`), which is what lets anchored dropdowns inside
a dialog escape the box.

The default is `overflow-visible`, which overrides the UA `dialog:modal { overflow: auto }`. The
UA `max-height: calc(100% - 6px - 2em)` still applies, so a dialog taller than the viewport that
did **not** opt into `overflowYAuto` clips with no scrollbar. Only 8 of 63 mount points opt in:

| File | Line |
| --- | --- |
| `dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/EditLiveChatCampaignDialog.vue` | 57 |
| `dashboard/components-next/Companies/CompanyCreateDialog.vue` | 59 |
| `dashboard/components-next/Contacts/ContactsForm/CreateNewContactDialog.vue` | 43 |
| `dashboard/components-next/captain/pageComponents/assistant/CreateAssistantDialog.vue` | 78 |
| `dashboard/components-next/captain/pageComponents/response/FaqSuggestionReviewDialog.vue` | 129 |
| `dashboard/components-next/recipes/RecipeDialog.vue` | 110 |
| `dashboard/routes/dashboard/settings/commerce/StoreDialog.vue` | 106 |
| `dashboard/routes/dashboard/settings/inbox/components/WhatsappManualMigrationDialog.vue` | 226 |

**Body scroll is never locked.** `Dialog.vue` imports no scroll-lock utility, unlike `SidePanel.vue`
which uses `useScrollLock` (`side-panel/SidePanel.vue:41`).

`position="top"` adds `.dialog-position-top { margin-top: clamp(2rem, 5vh, 5rem); margin-bottom: auto }`
(`:184-187`), which replaces the UA vertical `margin: auto`; horizontal auto margins survive, so
it stays horizontally centred. Two call sites use it:
`captain/pageComponents/response/FaqSuggestionReviewDialog.vue:129` and
`routes/dashboard/settings/inbox/components/WhatsappManualMigrationDialog.vue:226`.

### 2.6 RTL

Wrapped in `TeleportWithDirection to="body"` (`:118`) so `ltr:`/`rtl:` variants keep working after
teleport. The form carries `text-start` (`:132`). The footer is a plain `flex`, so Cancel/Confirm
mirror automatically with `dir`. No hard-coded `left`/`right` anywhere in the file.

### 2.7 Accessibility gaps (literal, not editorial)

- No `aria-labelledby` pointing at the `<h3>` (`:136-139`), and no `aria-describedby` for the
  description. The `<dialog>` element has **no** aria attributes at all (`:119-128`).
- No `role`/`aria-modal` is needed (native `<dialog>` supplies them), but the accessible name is
  therefore empty.
- Only `components-next/emoji-icon-picker/EmojiIconPicker.vue:147` and
  `components-next/side-panel/SidePanel.vue:118-121` declare `role="dialog"` in `components-next/`;
  `AssistantPlayground.vue:248` is the only `aria-labelledby` on an overlay-ish surface.

---

## 3. `components-next/side-panel/SidePanel.vue` — the only drawer

### 3.1 Props and API

| Prop | Type | Default | Validator | Line |
| --- | --- | --- | --- | --- |
| `title` | String | `''` | — | `side-panel/SidePanel.vue:8-11` |
| `description` | String | `''` | — | `:12-15` |
| `width` | String | `'xl'` | `['md','lg','xl','2xl','3xl']` | `:16-20` |
| `closeOnClickOutside` | Boolean | `true` | — | `:21-24` |

Emits `close`, `afterLeave` (`:29`; `afterLeave` exists so a `v-if`-mounted consumer can wait for
the slide-out before unmounting). Exposes `open()`, `close()` (`:89`) — ref-driven, like `Dialog`.

Slots: `header` (replaces title/description block), `header-actions` (sits left of the X),
default (body), `footer` (`:129-159`).

### 3.2 Geometry

Panel shell: `fixed z-50 flex flex-col w-[calc(100%-1.5rem)] overflow-hidden rounded-xl shadow-lg
outline outline-1 outline-n-container inset-y-3 end-3 bg-n-solid-1 will-change-transform` (`:122`),
plus `maxWidthClass` (`:123`).

| `width` | Class | px | Consumers |
| --- | --- | --- | --- |
| `md` | `max-w-md` | 448 | `routes/dashboard/settings/templates/TemplatePreviewDrawer.vue:71` |
| `lg` | `max-w-lg` | 512 | `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleDiffPanel.vue:123`, `components-next/captain/assistant/AssistantPlayground.vue:293` |
| `xl` (default) | `max-w-xl` | 576 | `components-next/captain/pageComponents/ConversationUsageDrawer.vue:80`, `components-next/captain/pageComponents/overview/AssistantDrilldownDrawer.vue:92`, `routes/dashboard/settings/reports/components/ReportDrilldownDrawer.vue:159` |
| `2xl` | `max-w-2xl` | 672 | **0** |
| `3xl` | `max-w-3xl` | 768 | `routes/dashboard/settings/automation/AutomationRuleForm.vue:295`, `components-next/captain/pageComponents/document/DocumentDetails.vue:219` |

Structure: `header` `px-6 py-5 border-b border-n-weak`, with `items-start` when the `header` slot
is used and `items-center` otherwise (`:125-128`); body `flex-1 min-h-0 px-6 py-5 overflow-y-auto`
(`:151`); `footer` `px-6 py-4 border-t border-n-weak`, rendered only if the slot is filled (`:154-159`).

### 3.3 Focus, Escape, click-outside, scroll

| Behaviour | Implementation | Line |
| --- | --- | --- |
| **No focus trap** | Focus is *moved* to the panel but Tab can walk back out into the page behind | `:58-61` |
| Initial focus | `panelRef.value?.focus()` in `@after-enter`, on `tabindex="-1"` aside — deliberately deferred so the layout-forcing work does not cost a frame of the slide (`:56-57` comment) | `:58-61`, `:121` |
| Focus restore | `previousActiveElement` captured in `open()`, refocused in `close()` if still `isConnected` | `:43-53`, `:67` |
| Scroll lock | `useScrollLock(document.body)`, set `true` in `onAfterEnter`, `false` in `close()` and `onBeforeUnmount` | `:41`, `:59`, `:66`, `:85-87` |
| Escape | `onKeyStroke('Escape', …)`; bails out if any `dialog[open]` exists, so a nested `<dialog>` keeps the key | `:76-83` |
| Click-outside | Overlay div `@click="onOverlayClick"`, gated on `closeOnClickOutside` | `:104`, `:72-74` |
| Aria | `role="dialog" aria-modal="true" :aria-label="title"` | `:118-120` |
| Close button | `Button ghost slate sm icon="i-lucide-x" :aria-label="$t('GENERAL.CLOSE')"` | `:141-148` |

`closeOnClickOutside` is declared but **no consumer sets it to `false`** — all 8 use the default.

### 3.4 Transitions and RTL

Two sibling `<Transition>`s inside one `TeleportWithDirection to="body"` (`:93`):
- Overlay: `fixed inset-0 z-50 bg-n-alpha-black1`, opacity 300ms in / 200ms out (`:94-106`).
- Panel: transform 300ms `cubic-bezier(0.4,0,0.2,1)` in / 200ms `ease-in` out, from
  `translate-x-[calc(100%+0.75rem)]` with an explicit `rtl:translate-x-[calc(-100%-0.75rem)]`
  counterpart (`:107-114`).

Position uses logical properties (`inset-y-3 end-3`, `:122`) and the header spacer uses `-me-2`
(`:139`), so the drawer slides from the inline end — right in LTR, left in RTL. This is the
**best-handled RTL case in the container system**.

---

## 4. `components/Modal.vue` — the legacy modal (global `<woot-modal>`)

Registered globally as `wootModal` / `<woot-modal>` by the deprecated kit at
`dashboard/components/index.js:16,35,41-48` (file header: *"[NOTE][DEPRECATED] … please do not add
new components to this file"*). `ModalHeader.vue` is registered the same way as `<woot-modal-header>`
(`index.js:15,36`).

**29 mount points**: 27 `<woot-modal>` tags plus 2 that import the component directly and render
`<Modal>` (`routes/dashboard/settings/canned/AddCanned.vue:85`,
`routes/dashboard/settings/canned/EditCanned.vue:92`). Three further wrapper components render it
internally (§4.4), and are themselves used globally as `<woot-confirm-delete-modal>`,
`<woot-confirm-modal>` and `<woot-delete-modal>`.

### 4.1 Props

| Prop | Type | Default | Line |
| --- | --- | --- | --- |
| `closeOnBackdropClick` | Boolean | `true` | `components/Modal.vue:8` |
| `showCloseButton` | Boolean | `true` | `:9` |
| `onClose` | Function | `null` | `:10` — **runtime-deprecated**, warns in DEV (`:60-67`) |
| `fullWidth` | Boolean | `false` | `:11` |
| `modalType` | String | `'centered'` | `:12` — `['centered','right-aligned']` via map at `:20-23` |
| `size` | String | `''` | `:13` — passed through as a raw class name (`:84`) |

`show` is a `defineModel` (`:17`). Emits `close` (`:16`).

### 4.2 Widths — a parallel, incompatible scale

| Variant | Rule | px | Line | Consumers |
| --- | --- | --- | --- | --- |
| default | `rounded-xl w-[37.5rem]` | 600, **no `max-w`** | `:81` | 25 of the 29 mount points |
| `size="medium"` | `max-w-[80%] w-[56.25rem]` | 900, capped at 80vw | `:109-111` | `components/widgets/modal/WootKeyShortcutModal.vue:39` |
| `size="modal-big"` | `.modal-big { @apply w-full }` | full | `:134-136` | `components/widgets/conversation/ContentTemplates/ContentTemplatesModal.vue:60`, `components/widgets/conversation/WhatsappTemplates/Modal.vue:76` |
| `full-width` | `items-center rounded-none flex h-full justify-center w-full` | full screen | `:82-84` | `components/widgets/conversation/components/GalleryView.vue:175-177` |
| `modal-type="right-aligned"` | `.modal-mask.right-aligned .modal-container { rounded-none h-full w-[30rem] }` | 480, full-height right drawer | `:138-144` | **0 — dead code** |

Mask: `flex items-center justify-center bg-n-alpha-black2 backdrop-blur-[4px] z-[9990] h-full
left-0 fixed top-0 w-full` (`:105`). Note `z-[9990]`, which is *below* `Popover`/`ContextMenu`'s
`z-[9999]`.

### 4.3 Behaviour

| Behaviour | Implementation | Line |
| --- | --- | --- |
| **No Teleport** | Renders in place. File-level `// [TODO] Use Teleport to move the modal to the end of the body` | `:2` |
| **No focus trap, no focus restore, no initial focus** | nothing in the file touches focus | — |
| **No scroll lock** | nothing | — |
| **No aria** | no `role`, no `aria-modal`, no accessible name | `:72-98` |
| Escape | `useEventListener(document, 'keydown', onKeydown)`, `e.code === 'Escape'` → `close()` + `stopPropagation()` — **not gated on topmost**, so stacked modals all close | `:50-58` |
| Backdrop click | mousedown-on-mask / mouseup-on-body pairing via `mousedownOnBackdrop` flag, with `// [TODO] Revisit this logic to use outside click directive` | `:28-48` |
| Close button | `Button ghost slate icon="i-lucide-x"` absolutely placed `ltr:right-2 rtl:left-2 top-2`, `z-10` | `:89-96` |
| Scroll | container `max-h-full overflow-auto` | `:79` |
| Transition | `<transition name="modal-fade">` — but the defined classes are `.modal-enter` / `.modal-leave` (Vue 2 names), not `.modal-fade-enter-from` etc., so **the transition is inert** | `:71`, `:146-154` |
| RTL | `rtl:text-right` on the container (`:79`) and a `ltr:/rtl:` close-button position (`:94`). The `.modal-mask` uses physical `left-0` (`:105`) — harmless since it is also `w-full` | — |

Styling is SCSS with nested descendant selectors that reach into consumer markup
(`.content { @apply p-8 }`, `form, .modal-content { @apply pt-4 pb-8 px-8 }`, `:112-130`), and one
consumer reaches back the other way with `:deep(.modal-container)`
(`modules/conversations/components/MessageContextMenu.vue:301`). Two consumers override positioning
from the outside with the identical copy-pasted hack
`class="!items-start [&>div]:!top-12 [&>div]:sticky"` —
`components/widgets/conversation/linear/IssuesList.vue:119` and
`routes/dashboard/conversation/contact/ContactNotes.vue:137` — the closest thing in the legacy
engine to `Dialog`'s `position="top"`.

`closeOnBackdropClick={false}` is genuinely used, by those same two call sites
(`IssuesList.vue:122`, `ContactNotes.vue:140`).

### 4.4 Wrappers built on it

| Wrapper | Role | Line |
| --- | --- | --- |
| `components/widgets/modal/ConfirmDeleteModal.vue` | type-the-name delete confirm, Vuelidate `isEqual` | `:64-91` |
| `components/widgets/modal/ConfirmationModal.vue` | promise-returning confirm (`showConfirmation()` resolves `true`/`false`) | `:35-51`, `:55-64` |
| `components/widgets/modal/DeleteModal.vue` | simple delete confirm | `:18-29` |
| `components/ModalHeader.vue` | `px-8 pt-8 pb-0` title + content + optional image | `:27-49` |

All three wrappers put their action row at the **end** (`justify-end gap-2`), the opposite of
`Dialog.vue`'s 50/50 `justify-between` footer.

---

## 5. `components-next/popover/Popover.vue` — the only responsive container

### 5.1 Props

| Prop | Type | Default | Validator | Line |
| --- | --- | --- | --- | --- |
| `align` | String | `'end'` | `['start','end']` | `popover/Popover.vue:14-18` |
| `disableMobileView` | Boolean | `false` | — | `:19-22` |
| `closeOnScroll` | Boolean | `true` | — | `:23-26` |
| `showContentBorder` | Boolean | `true` | — | `:27-30` |

Emits `show`, `hide` (`:33`). Exposes `show`, `hide`, `toggle` (`:131`). Slots: default (trigger,
receives `is-open`) and `content` (receives `hide`) (`:136`, `:158`, `:177`).

### 5.2 Two layouts

| Layout | Condition | Classes | Line |
| --- | --- | --- | --- |
| Desktop anchored | `isActive && !isMobile` | `flex flex-col bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl` + `fixed z-[9999]` + measured inline styles | `:164-179` |
| Mobile modal | `isActive && belowMd && !disableMobileView` | backdrop `fixed inset-0 z-[9999] flex items-start pt-[clamp(3rem,15vh,12rem)] justify-center bg-n-alpha-black1`; card `w-full max-w-lg max-h-[calc(100vh-4rem)] mx-4 bg-n-alpha-3 backdrop-blur-[100px] shadow-xl rounded-xl` | `:141-161` |

The breakpoint is `useBreakpoints(breakpointsTailwind).smaller('md')` → `< 768px` (`:40-42`).
`watch(isMobile, …)` re-measures when the viewport crosses back to desktop while open (`:93-97`).

Positioning comes from `useDropdownPosition(triggerRef, popoverRef, showPopover, { align })`
(`:45-50`) — see §7.

### 5.3 Dismissal

| Behaviour | Implementation | Line |
| --- | --- | --- |
| Click-outside | `v-on-click-outside` directive on both layouts, with `ignore: clickOutsideIgnore` | `:148-151`, `:167` |
| Ignore list | `['dialog.ProseMirror-prompt-backdrop', '[data-popover-content]']` | `:105-108` |
| Trigger re-click | `handleClickOutside` returns early if the click is inside the trigger (toggle handles it) | `:99-102` |
| Escape | `useKeyboardEvents({ Escape: { action, allowOnFocusedInput: true } })` | `:122-129` |
| Nested-overlay Escape | `isNestedOverlay()` walks `closest()` over the ignore selectors and lets the inner overlay keep the key — the comment explains the teleport ordering problem | `:110-120` |
| Close on scroll | capture-phase `window` scroll listener; closes once the trigger's `top` drifts more than `SCROLL_CLOSE_THRESHOLD = 24` px from its position at open; skips scrolls originating inside the popover | `:52-57`, `:71-85` |
| Focus trap | **none** | — |
| Scroll lock | **none** (even in the mobile modal layout) | — |
| Aria | **none** on either layout; the trigger is a bare `<span class="inline-flex" @click="toggle">` | `:135` |

Data attributes `data-popover-content` / `data-popover-backdrop` (`:143`, `:152`, `:168`) are the
cross-component contract that lets other surfaces ignore popover clicks — see
`components/widgets/conversation/ConversationSidebar.vue:44-53` and
`components-next/Campaigns/CampaignLayout.vue:35`.

Spec coverage: `components-next/popover/specs/Popover.spec.js` (244 lines) covers toggling, slot
`hide`, exposed methods, Escape incl. nested overlay, click-outside, the mobile switch, and
close-on-scroll thresholds.

### 5.4 Consumers (8)

| File | Note |
| --- | --- |
| `components-next/NewConversation/ComposeConversation.vue` | — |
| `components-next/NewConversation/components/ContentTemplateSelector.vue` | — |
| `components-next/NewConversation/components/WhatsAppOptions.vue` | — |
| `components-next/captain/pageComponents/overview/MetricHint.vue` | — |
| `components-next/message/CaptainGenerationDetails.vue` | — |
| `modules/contact/ContactDeleteModal.vue:60` | named "Modal", **is a Popover** |
| `modules/contact/ContactMergeModal.vue:72` | named "Modal", **is a Popover** |
| `routes/dashboard/settings/teams/TeamForm.vue` | — |

---

## 6. `components-next/dropdown-menu/` — two unrelated menu systems

### 6.1 `DropdownMenu.vue` (data-driven, 41 files)

Props (`dropdown-menu/DropdownMenu.vue:10-55`): `menuItems` (Array, `[]`), `menuSections` (Array,
`[]`), `thumbnailSize` (Number, `20`), `roundedThumbnail` (Boolean, `true`), `showSearch` (Boolean,
`false`), `searchPlaceholder` (String, `''`), `isSearching` (Boolean, `false`), `labelClass`
(String, `''`), `disableLocalFiltering` (Boolean, `false`), `isLoading` (Boolean, `false`),
`emptyStateMessage` (String, `'DROPDOWN_MENU.EMPTY_STATE'`). Emits `action`, `search`, `empty` (`:57`).
Slots: `thumbnail`, `icon`, `label`, `trailing-icon` (all item-scoped), `footer` (`:196-227`, `:300-302`).

Shell: `bg-n-alpha-3 backdrop-blur-[100px] border-0 outline outline-1 outline-n-container
absolute rounded-xl z-50 flex flex-col min-w-[136px] shadow-lg pt-2 overflow-hidden` (`:140`).

**It has no positioning logic and no width of its own beyond `min-w-[136px]`.** `absolute` with no
offsets means every consumer hand-writes the anchor and the width in its `class` attribute. The
item markup is duplicated verbatim between the sectioned and flat branches (`:182-228` vs `:239-285`).

Interaction: no `role="menu"`/`role="menuitem"`, no arrow-key navigation, no Escape, no
click-outside — all of that lives in the consumer. The search input self-focuses on mount
(`:131-135`). Items are `<button type="button">` with `hover:bg-n-alpha-1 dark:hover:bg-n-alpha-2`
and a hard-coded destructive colour keyed on `item.action === 'delete'` (`:189-190`).

#### Consumer-supplied anchoring and width — the full census

| File:line | Class on `<DropdownMenu>` |
| --- | --- |
| `modules/search/components/SearchContactAgentSelector.vue:235` | `mt-1 ltr:left-0 rtl:right-0 top-full w-64 max-h-80` |
| `modules/search/components/SearchDateRangeSelector.vue:208` | `mt-1 ltr:left-0 rtl:right-0 top-full w-64` |
| `modules/search/components/SearchInboxSelector.vue:120` | `mt-1 ltr:right-0 rtl:left-0 top-full w-64 max-h-80` |
| `components/widgets/conversation/conversationBulkActions/BulkLabelActions.vue:160` | `w-60 max-h-80` (no anchor at all) |
| `components/widgets/conversation/conversationBulkActions/BulkTeamActions.vue:105` | `ltr:-right-2 rtl:-left-2 bottom-8 w-60 max-h-80` |
| `components/widgets/conversation/conversationBulkActions/BulkUpdateActions.vue:104` | `ltr:-right-[4.5rem] rtl:-left-[4.5rem] ltr:2xl:right-0 rtl:2xl:left-0 bottom-8 w-36` |
| `components/widgets/conversation/conversationBulkActions/BulkAgentActions.vue:139` | `ltr:-right-10 rtl:-left-10 ltr:2xl:right-0 rtl:2xl:left-0 bottom-8 w-60 max-h-80` |
| `components/widgets/conversation/MoreActions.vue:115` | `mt-1 ltr:right-0 rtl:left-0 top-full` |
| `components-next/phonenumberinput/PhoneNumberInput.vue:212` | `z-[100] w-48 mt-2 ltr:left-0 rtl:right-0 top-full max-h-52` |
| `components-next/HelpCenter/LocaleCard/LocaleCard.vue:137` | `ltr:right-0 rtl:left-0 mt-1 top-full z-60 min-w-[150px]` |
| `components-next/HelpCenter/ArticleCard/ArticleCard.vue:249` | `mt-1 end-0 top-full w-40` |
| `components-next/HelpCenter/Pages/CategoryPage/CategoryHeaderControls.vue:152` | `left-0 w-40 mt-2 xl:right-0 top-full max-h-60` |
| `components-next/HelpCenter/Pages/PortalSettingsPage/PortalLayoutContentSettings.vue:276` | `mt-1 w-52 top-full ltr:left-0 rtl:right-0` |
| `components-next/HelpCenter/Pages/ArticlePage/ArticleHeaderControls.vue:161` | `left-0 w-40 max-w-[300px] mt-2 xl:right-0 top-full max-h-60` |
| `components-next/HelpCenter/Pages/ArticlePage/ArticleHeaderControls.vue:191` | `left-0 w-48 mt-2 xl:right-0 top-full max-h-60` |
| `components-next/HelpCenter/Pages/ArticlePage/ArticlesPage.vue:464` | `right-0 w-48 mt-2 top-full max-h-60` |
| `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditorControls.vue:198` | `z-[100] w-48 mt-2 ltr:left-0 rtl:right-0 top-full max-h-60` |
| `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditorControls.vue:234` | `w-48 mt-2 z-[100] left-0 top-full max-h-60` |
| `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditorHeader.vue:328` | `mt-2 ltr:right-0 rtl:left-0 top-full` |
| `components-next/HelpCenter/CategoryCard/CategoryCard.vue:123` | `mt-1 ltr:right-0 rtl:left-0 xl:ltr:left-0 xl:rtl:right-0 top-full z-60` |
| `components-next/Companies/CompaniesHeader/components/CompanyMoreActions.vue:41` | `ltr:right-0 rtl:left-0 mt-1 w-52 top-full` |
| `components-next/Contacts/ContactsHeader/components/ContactMoreActions.vue:219` | `ltr:right-0 rtl:left-0 mt-1 w-60 top-full` |
| `components-next/label/AddLabel.vue:38` | `z-[100] w-48 mt-2 ltr:left-0 rtl:right-0 top-full max-h-52` |
| `components-next/captain/pageComponents/overview/v2/ResolutionTrendCard.vue:186` | `mt-1 min-w-48 end-0 top-full` |
| `components-next/captain/pageComponents/overview/RangeSelector.vue:130` | `mt-1 ltr:right-0 rtl:left-0 top-full` |
| `components-next/captain/pageComponents/customTool/CustomToolCard.vue:136` | `mt-1 ltr:right-0 rtl:right-0 top-full` |
| `components-next/captain/assistant/AssistantCard.vue:103` | `mt-1 ltr:right-0 rtl:left-0 top-full` |
| `components-next/captain/assistant/ResponseCard.vue:193` | `mt-1 ltr:right-0 rtl:right-0 top-full` |
| `components-next/captain/assistant/InboxCard.vue:100` | `mt-1 ltr:right-0 rtl:left-0 top-full` |
| `components-next/captain/assistant/DocumentFiltersBar.vue:146` | `top-full mt-2 ltr:left-0 rtl:right-0` |
| `components-next/captain/assistant/DocumentCard.vue:220` | `top-full mt-1 ltr:right-0 rtl:left-0 xl:ltr:right-0 xl:rtl:left-0` |
| `components-next/NewConversation/components/InboxSelector.vue:93` | `ltr:left-0 rtl:right-0 z-[100] top-8 max-h-56 w-fit max-w-sm dark:!outline-n-slate-5` |
| `components-next/Calls/CallsFilterBar.vue:206` | `mt-1 start-0 top-full w-44` |
| `components-next/Calls/CallsFilterBar.vue:241` | `mt-1 end-0 top-full w-56 max-h-72` |
| `components-next/Calls/CallsFilterBar.vue:264` | `mt-1 end-0 top-full w-56 max-h-80` |
| `components-next/CustomAttributes/ListAttribute.vue:72` | `w-48 mt-2 top-full` (no horizontal anchor) |
| `components-next/sidebar/SidebarSortMenu.vue:195` | `w-60 !fixed` (positioned by `useDropdownPosition`) |
| `components-next/taginput/TagInput.vue:250` | `ltr:left-0 rtl:right-0 z-[100] top-8 max-h-56 w-[inherit] max-w-md dark:!outline-n-slate-5` |
| `routes/dashboard/settings/auditlogs/components/AuditLogFilters.vue:209` | `mt-2 min-w-52 max-h-80 top-full start-0` |
| `routes/dashboard/settings/templates/Index.vue:378` | `mt-2 min-w-52 top-full ltr:left-0 rtl:right-0` |
| `routes/dashboard/settings/reports/components/heatmaps/BaseHeatmapContainer.vue:319` | `mt-1 ltr:right-0 rtl:left-0 xl:ltr:right-0 xl:rtl:left-0 top-full !min-w-56 max-w-56 max-h-96` |
| `routes/dashboard/settings/reports/components/heatmaps/HeatmapDateRangeSelector.vue:208` | `mt-1 ltr:right-0 rtl:left-0 xl:ltr:right-0 xl:rtl:left-0 top-full` |
| `components-next/ConversationWorkflow/ConversationRequiredAttributes.vue:147` | (no class) |

Distinct menu widths in that list: `w-36`, `w-40`, `w-44`, `w-48`, `w-52`, `w-56`, `w-60`, `w-64`,
`min-w-[136px]` (default), `min-w-[150px]`, `min-w-48`, `min-w-52`, `!min-w-56`, `w-fit max-w-sm`,
`w-[inherit] max-w-md`. Distinct max-heights: `max-h-52`, `max-h-56`, `max-h-60`, `max-h-72`,
`max-h-80`, `max-h-96`, none. Distinct gaps: `mt-1`, `mt-2`, none. Distinct z-indexes: inherited
`z-50`, `z-60`, `z-[100]`.

### 6.2 `dropdown-menu/base/*` (primitives, 10 files)

| File | What it is | Key lines |
| --- | --- | --- |
| `base/DropdownContainer.vue` | state + outside-click + teleport decision. `useToggle`, `provideDropdownContext({isOpen, toggle, closeMenu})`, `v-on-click-outside` with `ignore: ['[data-dropdown-menu]']`. `getTrigger()` is a getter not a computed, so consumers may swap the trigger element (`:14-16`). Root is `relative space-y-2`. | `:9-32`, `:36-50` |
| `base/DropdownFloating.vue` | the teleported variant. `TeleportWithDirection to="body"`, `data-dropdown-menu`, `useDropdownPosition(trigger, menuRef, true, { align: 'start' })`, inner `[&>*]:!static` to neutralise the body's own `absolute` | `:15-17`, `:20-32` |
| `base/DropdownBody.vue` | the surface. `absolute` wrapper + `ul` with `bg-n-alpha-3 backdrop-blur-[100px] border rounded-xl shadow-sm py-2 n-dropdown-body gap-2 grid list-none px-2 reset-base relative`. `strong` prop swaps `border-n-weak`→`border-n-strong` and adds a `::before` extra blur layer as an explicit workaround for Chrome's stacked-`backdrop-blur` bug (crbug 40835530) | `:3-23`, `:26-34` |
| `base/DropdownItem.vue` | polymorphic item — `router-link` / `a` / `button` / `div` chosen from `link`/`nativeLink`/`click`. `preserveOpen` keeps the menu open. `inheritAttrs: false`. `flex text-left rtl:text-right items-center p-2 reset-base text-sm text-n-slate-12 w-full border-0` | `:6-39`, `:42-62` |
| `base/DropdownSection.vue` | titled group, `height` prop defaults to `max-h-96`, inner `ul` is `overflow-y-auto` | `:2-11`, `:14-28` |
| `base/DropdownSeparator.vue` | `h-0 border-b border-n-strong -mx-2` | `:2` |
| `base/provider.js` | `DropdownControl` + `DropdownTeleport` symbols. `useDropdownContext()` **throws** if there is no parent container (`:9-14`). `provideDropdownTeleport()` opts a whole subtree into body-rendering | `:3-32` |
| `base/index.js` | barrel; note `DropdownFloating` is **not** exported | `:7-13` |

`n-dropdown-body`, `n-dropdown-item`, `n-dropdown-section` are **marker classes with no CSS
definition anywhere** — a repo-wide search finds only the three template usages above.

Consumers: `components-next/copilot/ToggleCopilotAssistant.vue`,
`components-next/filter/inputs/{FilterSelect,MultiSelect,SingleSelect}.vue`,
`components-next/sidebar/{SidebarAccountSwitcher,SidebarProfileMenu,SidebarProfileMenuStatus}.vue`,
`components/widgets/WootWriter/CopilotMenuBar.vue`,
`routes/dashboard/settings/automation/AutomationRuleForm.vue`,
`routes/dashboard/settings/captain/components/ModelDropdown.vue`.

---

## 7. `composables/useDropdownPosition.js` — the shared positioner

Constants: `FALLBACK_SIZE = 200`, `SAFE_MARGIN = 16`, `GAP = 8` (`:4-6`).
Signature `useDropdownPosition(triggerRef, dropdownRef, enabled, { container, margin, align })`
(`:19-24`). Returns `{ position, fixedPosition, updatePosition }` (`:127`).

| Concern | Behaviour | Line |
| --- | --- | --- |
| RTL detection | reads the DOM directly: `document.querySelector('#app[dir]')?.getAttribute('dir') === 'rtl'` | `:30-32` |
| Align flip | `anchorLeft = (align === 'start') !== isRTL` | `:35` |
| Vertical | prefers below; flips above only if it actually fits; otherwise picks the larger side | `:37-46`, `:79-83` |
| `position` (relative mode) | returns `{ class: 'top-full mt-2' \| 'bottom-full mb-2', style: {left\|right} }`, optionally constrained to a `container` | `:49-68` |
| `fixedPosition` (teleport mode) | returns `{ class: 'fixed z-[9999]', style }` with `top`/`bottom` + a computed `maxHeight` and a horizontal clamp to `margin` | `:71-111` |
| Re-measure | `watch(enabled)` calls `updatePosition()` on open "to ensure RTL state is current" | `:119-125` |

Used by `popover/Popover.vue:45`, `dropdown-menu/base/DropdownFloating.vue:15`,
`components-next/sidebar/SidebarSortMenu.vue:55`.

Note the RTL read at `:30-32` bypasses the `accounts/isRTL` store getter that
`TeleportWithDirection.vue:17` uses — two sources of truth for the same fact.

---

## 8. `components-next/selectmenu/SelectMenu.vue` — legacy, 3 consumers

Props: `options` (Array, required), `modelValue` (String, required), `label` (String, required),
`subMenuPosition` (String, `'right'`, validator `['right','left','bottom']`) (`selectmenu/SelectMenu.vue:5-25`).
Emits `update:modelValue` (`:27`).

| Concern | Finding | Line |
| --- | --- | --- |
| Outside click | `v-on-clickaway` — the **legacy** directive, the only overlay in `components-next/` still on it | `:45` |
| Escape | **none** | — |
| Teleport | **none** — `absolute` inside a `relative` parent, so it clips inside any scrolling ancestor | `:44-46`, `:61` |
| Width | `max-w-64` on the panel, `!w-fit max-w-40` on the trigger | `:61`, `:54` |
| z-index | `z-40` — lower than every other menu in the system | `:61` |
| RTL | explicit `ltr:`/`rtl:` pairs for all three placements | `:62-68` |
| Item alignment | `!justify-end` — items are end-aligned, unlike every other menu | `:79` |

Consumers: `components-next/Companies/CompaniesHeader/components/CompanySortMenu.vue`,
`components-next/Contacts/ContactsHeader/components/ContactSortMenu.vue`,
`components/widgets/conversation/ConversationBasicFilter.vue`.

---

## 9. `components-next/TeleportWithDirection.vue`

28 lines. One prop `to` (String, `'body'`) (`:10-15`). Reads `accounts/isRTL` via `useMapGetter`
(`:17`) and wraps the slot in `<div :dir="contentDirection">` inside `<Teleport>` (`:22-27`). The
file-head comment states the purpose: preserve `ltr:`/`rtl:` variant resolution for content
teleported out of the `[dir]` container.

The app root that supplies `dir` is `dashboard/App.vue:139-141` (`id="app" :dir="isRTL ? 'rtl' : 'ltr'"`).
`isRTL` is the getter at `dashboard/store/modules/accounts.js:34`.

Consumers (10): `dialog/Dialog.vue:118`, `side-panel/SidePanel.vue:93`, `popover/Popover.vue:139`,
`dropdown-menu/base/DropdownFloating.vue:21`, `preview-picker/CaretAnchoredPicker.vue:182`,
`sidebar/SidebarCollapsedPopover.vue:109`, `sidebar/SidebarSortMenu.vue:186`,
`components/ChatList.vue`, `components/ui/ContextMenu.vue:95`,
`components/widgets/conversation/components/GalleryView.vue:174`.

`components-next/year-in-review/YearInReviewModal.vue:192` uses a **raw** `<Teleport to="body">`
instead, so it loses the direction context.

---

## 10. Every other overlay in the tree (ad-hoc, no shared base)

| Component | Kind | Surface / width | Dismissal | Line |
| --- | --- | --- | --- | --- |
| `components/ui/ContextMenu.vue` | context menu | `fixed outline-none z-[9999]`; `PADDING = 16` viewport clamp, measured via `useElementBounding` | `focusout` when focus leaves; `useScrollLock` on an **injected** `contextMenuElementTarget` | `:35-50`, `:95-105`, `:21-30`, `:80-87` |
| `components-next/sidebar/SidebarCollapsedPopover.vue` | flyout | `fixed z-[100] min-w-[200px] max-w-[280px]`, inner card `w-56`; list `max-h-[400px] overflow-y-auto` | `onClickOutside` with `ignore: ['[data-popover-content]']` | `:112`, `:121`, `:129`, `:36-38` |
| `components-next/sidebar/SidebarSortMenu.vue` | menu | `w-60 !fixed` via `useDropdownPosition` | `vOnClickOutside` | `:195`, `:55` |
| `components-next/preview-picker/CaretAnchoredPicker.vue` | anchored picker | `fixed z-[9999]` | `vOnClickOutside` + `Escape` | `:194`, `:154` |
| `components-next/feature-spotlight/FeatureSpotlightPopover.vue` | coach mark | `absolute top-full mt-6 … w-80 z-20` + a rotated arrow pseudo-element | `vOnClickOutside` | `:53-56`, `:4` |
| `components-next/AssignmentPolicy/components/CardPopover.vue` | popover | `absolute … z-50 max-w-96 min-w-80 max-h-[20rem] overflow-y-auto`, `backdrop-blur-[50px]` | `vOnClickOutside` | `:65`, `:3` |
| `components-next/HelpCenter/Pages/ArticleEditorPage/ArticlePendingChangesPopover.vue` | popover | `absolute z-50 … w-96 end-0 top-full` | `vOnClickOutside` + `onKeyStroke('Escape')`, both guarded mid-action | `:84`, `:49`, `:73` |
| `components/widgets/conversation/components/SLAPopoverCard.vue` | popover | `absolute … w-96 z-50 max-h-96 overflow-auto` | none in file | `:44` |
| `routes/dashboard/helpcenter/components/ArticleSearch/SearchPopover.vue` | full-screen search | backdrop `fixed top-0 left-0 z-50 w-screen h-screen`; panel `z-[1000] max-w-[720px] md:w-[20rem] lg:w-[24rem] xl:w-[28rem] 2xl:w-[32rem] h-[calc(100vh-20rem)] max-h-[40rem]` — **physical** `top-0 left-0` | — | `:136`, `:140` |
| `components-next/year-in-review/YearInReviewModal.vue` | full-screen takeover | `fixed inset-0 z-[9999] bg-black font-interDisplay`; raw `<Teleport>` | `Escape` | `:195`, `:192`, `:172` |
| `components-next/year-in-review/ShareModal.vue` | modal | `fixed inset-0 bg-black bg-opacity-90 … z-[10001]` — the highest z-index in the dashboard | — | `:179` |
| `components/widgets/WootWriter/Editor.vue` (ProseMirror prompt) | native `<dialog>` from the editor lib | `.ProseMirror-prompt { … w-96 !important }`, `::backdrop { bg-n-alpha-black1 backdrop-blur-[4px] }` | library-owned | `:1100-1124` |

The ProseMirror prompt is the reason three different components carry the
`'dialog.ProseMirror-prompt-backdrop'` escape hatch: `popover/Popover.vue:106`,
`components/widgets/conversation/ConversationSidebar.vue:48`,
`components-next/Campaigns/CampaignLayout.vue:35`. `Dialog.vue:99-108` and `SidePanel.vue:78-79`
handle the same case generically via `dialog[open]` queries.

---

## 11. Consolidated width inventory (the answer to "every different modal width")

### Centred modals

| px | Source | Component | Mount points |
| --- | --- | --- | --- |
| 384 | `max-w-sm` | `Dialog` `width="sm"` | 0 (dead) |
| 384 | `w-96` | ProseMirror prompt, `SLAPopoverCard`, `ArticlePendingChangesPopover` | 3 |
| 448 | `max-w-md` | `Dialog` `width="md"` | 8 |
| 512 | `max-w-lg` | `Dialog` default + explicit | 47 |
| 512 | `max-w-lg` | `Popover` mobile modal card | all 8 popovers, < 768px |
| 576 | `max-w-xl` | `Dialog` `width="xl"` | 1 (dynamic) |
| 600 | `w-[37.5rem]` | legacy `Modal` default — **no `max-w`** | 25 |
| 672 | `max-w-2xl` | `Dialog` `width="2xl"` | 3 |
| 720 | `max-w-[720px]` | `SearchPopover` | 1 |
| 768 | `max-w-3xl` | `Dialog` `width="3xl"` | 4 |
| 900 | `w-[56.25rem] max-w-[80%]` | legacy `Modal` `size="medium"` | 1 |
| 100% | `.modal-big { w-full }` | legacy `Modal` `size="modal-big"` | 2 |
| 100vw/vh | `full-width` | legacy `Modal` — `GalleryView` | 1 |
| 100vw/vh | `fixed inset-0` | `YearInReviewModal`, `ShareModal` | 2 |

**Fourteen distinct centred-modal widths across three engines, for what is largely the same job.**

### Drawers

| px | Source | Mount points |
| --- | --- | --- |
| 448 / 512 / 576 / 672 / 768 | `SidePanel` `md`/`lg`/`xl`/`2xl`/`3xl`, all capped by `w-[calc(100%-1.5rem)]` | 1 / 2 / 3 / 0 / 2 |
| 480 | legacy `Modal` `modal-type="right-aligned"` (`w-[30rem]`, full height, square corners) | 0 (dead) |

### Which page uses which component

| Area | Container | Representative file:line |
| --- | --- | --- |
| Contacts, Companies, Segments | `Dialog` (`3xl` for create, `lg` for confirms) | `components-next/Contacts/ContactsForm/CreateNewContactDialog.vue:43`, `.../ConfirmContactDeleteDialog.vue:46` |
| Commerce (Salla/Shopify/Zid/Store) | `Dialog` `md` | `routes/dashboard/settings/commerce/SallaConnectDialog.vue:121` |
| Help Center (all dialogs) | `Dialog` `lg` | `components-next/HelpCenter/Pages/LocalePage/AddLocaleDialog.vue:120` |
| Captain | `Dialog` `lg`/`2xl`/`3xl` + `SidePanel` `xl`/`3xl` | `components-next/captain/pageComponents/customTool/CreateCustomToolDialog.vue:70`, `.../document/DocumentDetails.vue:219` |
| Automations | `SidePanel` `3xl` | `routes/dashboard/settings/automation/AutomationRuleForm.vue:295` |
| Reports drill-down | `SidePanel` `xl` | `routes/dashboard/settings/reports/components/ReportDrilldownDrawer.vue:159` |
| WhatsApp templates | `SidePanel` `md` | `routes/dashboard/settings/templates/TemplatePreviewDrawer.vue:71` |
| Agents, Labels, Attributes, Canned, SLA, Webhooks, Custom roles, Dashboard apps, Integration hooks | legacy `<woot-modal>` 600px | `routes/dashboard/settings/agents/Index.vue:280`, `.../labels/Index.vue:192`, `.../attributes/AddAttribute.vue:164`, `.../canned/Index.vue:249`, `.../sla/Index.vue:302`, `.../integrations/Webhooks/Index.vue:189`, `.../customRoles/Index.vue:187`, `.../integrations/DashboardApps/DashboardAppModal.vue:114`, `.../integrations/IntegrationHooks.vue:148` |
| Keyboard shortcuts | legacy `<woot-modal size="medium">` 900px | `components/widgets/modal/WootKeyShortcutModal.vue:39` |
| WhatsApp / content template pickers (conversation) | legacy `<woot-modal size="modal-big">` | `components/widgets/conversation/WhatsappTemplates/Modal.vue:76`, `.../ContentTemplates/ContentTemplatesModal.vue:60` |
| Attachment gallery | legacy `<woot-modal full-width>` | `components/widgets/conversation/components/GalleryView.vue:175` |
| Contact merge / delete | **`Popover`** | `modules/contact/ContactMergeModal.vue:72`, `modules/contact/ContactDeleteModal.vue:60` |
| Linear issue create/link | legacy `<woot-modal>` + external override classes | `components/widgets/conversation/linear/IssuesList.vue:119` |
| Snooze (custom time) | legacy `<woot-modal>` | `components/widgets/conversation/conversationBulkActions/Index.vue:207`, `routes/dashboard/commands/CmdBarConversationSnooze.vue:65` |
| Flows | `Dialog` `lg` | `routes/dashboard/settings/flows/Index.vue:299,332`, `routes/dashboard/settings/flows/FlowBuilder.vue:514` |
| Recipes | `Dialog` `2xl` | `components-next/recipes/RecipeDialog.vue:110` |

---

## 12. Mobile: what happens at 390px

### Is there any sheet / bottom-drawer pattern?

**No.** Zero matches for `bottomsheet`, `bottom-sheet`, or a `sheet` component token across
`dashboard/` and `shared/`; zero uses of `translate-y-full`; the only `fixed … bottom-0` hits are
`components-next/EmptyStateLayout.vue:40` (a fade gradient) and
`components/widgets/WootWriter/ReplyBottomPanel.vue:392` (a full-cover loading veil).

### `Dialog` at 390px

The project is on `tailwindcss ^3.4.19` (`package.json:149`), whose preflight resets **only**
`dialog { padding: 0 }` (`node_modules/tailwindcss/src/css/preflight.css:313-318`) and leaves the
UA `dialog:modal` rules intact. So:

| Aspect | At 390px |
| --- | --- |
| Width | `w-full` + `max-w-lg` (512) is overridden by the UA `max-width: calc(100% - 6px - 2em)` ≈ **352px**. Content area after the form's `p-6` ≈ **304px**. |
| Position | UA `margin: auto` keeps it centred; `position="top"` pins it `clamp(2rem,5vh,5rem)` from the top instead (`dialog/Dialog.vue:184-187`). |
| Height | UA `max-height: calc(100% - 6px - 2em)`. With the default `overflow-visible` (`:125`), taller content clips with no scrollbar. |
| Footer | Still the same single `justify-between` row of two 50/50 buttons (`:149-171`). **No stacking, no full-width-stacked variant, no safe-area padding.** |
| Breakpoint logic | **None.** `Dialog.vue` contains no `sm:`/`md:` variant and no `useBreakpoints`. |

So a 3xl dialog (`CreateNewContactDialog`, `CompanyCreateDialog`, `FaqSuggestionReviewDialog`,
`WhatsappManualMigrationDialog`) and an `md` confirm dialog render at the **same** ~352px on a
phone — the `width` prop is a no-op below ~480px.

### `SidePanel` at 390px

`w-[calc(100%-1.5rem)]` + `inset-y-3 end-3` (`side-panel/SidePanel.vue:122`) → a **366 × (100vh − 24px)**
rounded card inset 12px on all sides, sliding in from the inline end. It is the closest thing to a
mobile-correct container in the system, but like `Dialog` the `width` prop collapses: `md` and `3xl`
are identical below ~792px.

### Legacy `Modal` at 390px

The container is `w-[37.5rem]` = **600px with no `max-width`** (`components/Modal.vue:81`) inside a
`w-full` flex mask (`:105`). At 390px the modal is wider than the viewport and overflows
horizontally. Only `size="medium"` carries a cap (`max-w-[80%]`, `:109-111`). This affects the 25
default-size call sites — i.e. most of Settings (agents, labels, attributes, canned responses, SLA,
webhooks, custom roles, dashboard apps, integration hooks) plus conversation-side surfaces
(`ContactNotes.vue:137`, `InboxItemHeader.vue:150`, `EmailTranscriptModal.vue:103`,
`MessageContextMenu.vue:173`, `CmdBarConversationSnooze.vue:65`).

### `Popover` at 390px

The only container that changes shape: below `md` it abandons anchoring and renders a top-anchored
centred modal, `w-full max-w-lg mx-4 max-h-[calc(100vh-4rem)]` with its own backdrop
(`popover/Popover.vue:141-161`). `disableMobileView` opts out (`:19-22`, `:42`).

### `DropdownMenu` at 390px

No responsive behaviour and no viewport clamping in the component. Menus anchored with
`ltr:-right-[4.5rem]` (`BulkUpdateActions.vue:104`) or `ltr:-right-10` (`BulkAgentActions.vue:139`)
or fixed `w-64` (`modules/search/components/*`) can exceed a 390px viewport. Only consumers that go
through `useDropdownPosition` (the three in §7) get a `SAFE_MARGIN = 16` clamp.

---

## 13. Inconsistencies, with evidence

| # | Issue | Evidence | Severity |
| --- | --- | --- | --- |
| 1 | Two live modal engines with incompatible width scales, both actively used across Settings | `dialog/Dialog.vue:71-82` (448/512/576/672/768) vs `components/Modal.vue:81,109-111,134-136` (600/900/full); 29 legacy mount points remain | high |
| 2 | Legacy `Modal` is 600px fixed with no `max-width` — overflows below 600px | `components/Modal.vue:81`, mask `:105` | high |
| 3 | `SidePanel` has no focus trap: it focuses the panel and restores focus, but Tab walks into the page behind | `side-panel/SidePanel.vue:58-61,67`; no `trapFocus`/`useFocusTrap` import | high |
| 4 | Legacy `Modal` has no Teleport, focus management, scroll lock, `role` or `aria-modal` | `components/Modal.vue:2` (TODO), `:72-98` | high |
| 5 | `Dialog` never locks body scroll, while `SidePanel` does — the page scrolls behind an open modal | `dialog/Dialog.vue` (no `useScrollLock`) vs `side-panel/SidePanel.vue:41,59,66` | high |
| 6 | `DropdownMenu` ships no positioning; 41 consumers hand-roll anchor, width, gap and z-index, producing 15 widths / 6 max-heights / 3 z-indexes | census in §6.1 | high |
| 7 | RTL bug: `ltr:right-0 rtl:right-0` pins the menu to the physical right in both directions | `components-next/captain/pageComponents/customTool/CustomToolCard.vue:136`, `components-next/captain/assistant/ResponseCard.vue:193` | high |
| 8 | RTL bug: physical `left-0`/`right-0` with no direction variant on dropdowns | `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditorControls.vue:234`, `.../ArticlePage/ArticleHeaderControls.vue:161,191`, `.../ArticlePage/ArticlesPage.vue:464`, `.../CategoryPage/CategoryHeaderControls.vue:152` | high |
| 9 | `Dialog` body clips with no scrollbar unless `overflowYAuto` is passed; only 8 of 63 pass it | `dialog/Dialog.vue:47-50,125`; list in §2.5 | high |
| 10 | `Dialog` has **no close (X)** control, so `:show-cancel-button="false"` leaves only Escape/click-outside | `dialog/Dialog.vue:148-172` | medium |
| 11 | `Dialog` has no `aria-labelledby`/`aria-describedby` — the native dialog has no accessible name | `dialog/Dialog.vue:119-128,136-139` | medium |
| 12 | Footer conventions disagree: `Dialog` = 50/50 `justify-between` full-width pair; legacy wrappers = `justify-end gap-2` auto-width pair; `SidePanel` = consumer-defined | `dialog/Dialog.vue:149-171`; `components/widgets/modal/{DeleteModal.vue:25,ConfirmationModal.vue:59,ConfirmDeleteModal.vue:75}`; `side-panel/SidePanel.vue:154-159` | medium |
| 13 | Three outside-click mechanisms coexist | `OnClickOutside` component (`dialog/Dialog.vue:3,129`), `vOnClickOutside` directive (`popover/Popover.vue:2,167`), `v-on-clickaway` legacy (`selectmenu/SelectMenu.vue:45`) | medium |
| 14 | Two sources of truth for RTL | store getter via `TeleportWithDirection.vue:17` vs DOM query `document.querySelector('#app[dir]')` in `composables/useDropdownPosition.js:30-32` | medium |
| 15 | Unmanaged z-index ladder with no tokens: `z-40` → `z-50` → `z-60` → `z-[100]` → `z-[1000]` → `z-[9990]` → `z-[9999]` → `z-[10001]` | `selectmenu/SelectMenu.vue:61`; `side-panel/SidePanel.vue:102,122`; `dropdown-menu/DropdownMenu.vue:140`; `HelpCenter/LocaleCard/LocaleCard.vue:137`; `label/AddLabel.vue:38`; `SearchPopover.vue:140`; `components/Modal.vue:105`; `popover/Popover.vue:144`, `ui/ContextMenu.vue:98`; `year-in-review/ShareModal.vue:179` | medium |
| 16 | Legacy `Modal`'s transition is inert — `name="modal-fade"` but the CSS defines Vue-2 `.modal-enter`/`.modal-leave` | `components/Modal.vue:71` vs `:146-154` | medium |
| 17 | Destructive confirmations rendered as anchored popovers, not modals | `modules/contact/ContactDeleteModal.vue:60`, `modules/contact/ContactMergeModal.vue:72` (both `<Popover>`) | medium |
| 18 | Legacy `Modal` styles consumer internals via descendant SCSS, and consumers style back in — including an identical copy-pasted top-align hack in two files | `components/Modal.vue:112-130`; `modules/conversations/components/MessageContextMenu.vue:301` (`:deep(.modal-container)`); `components/widgets/conversation/linear/IssuesList.vue:119` and `routes/dashboard/conversation/contact/ContactNotes.vue:137` (both `!items-start [&>div]:!top-12 [&>div]:sticky`) | medium |
| 19 | Declared-but-unused API: `Dialog width="sm"`, `SidePanel width="2xl"`, `SidePanel closeOnClickOutside={false}`, `Modal modalType="right-aligned"` | `dialog/Dialog.vue:54`; `side-panel/SidePanel.vue:19,21-24`; `components/Modal.vue:12,138-144` | low |
| 20 | `DropdownMenu` duplicates ~45 lines of item markup between the sectioned and flat branches | `dropdown-menu/DropdownMenu.vue:182-228` vs `:239-285` | low |
| 21 | `n-dropdown-body` / `n-dropdown-item` / `n-dropdown-section` are marker classes with no CSS anywhere | `base/DropdownBody.vue:29`, `base/DropdownItem.vue:43`, `base/DropdownSection.vue:15` | low |
| 22 | `base/index.js` omits `DropdownFloating`, so the teleport variant must be deep-imported | `dropdown-menu/base/index.js:7-13` |low |
| 23 | `YearInReviewModal` uses a raw `<Teleport>`, losing the RTL direction context | `year-in-review/YearInReviewModal.vue:192` vs the 10 `TeleportWithDirection` consumers | low |
| 24 | `DropdownMenu` has no `role="menu"`/`menuitem` and no arrow-key navigation | `dropdown-menu/DropdownMenu.vue:138-303`; only `SidePanel.vue:118` and `EmojiIconPicker.vue:147` declare `role="dialog"` in `components-next/` | medium |
| 25 | `Popover`'s mobile modal layout has no scroll lock and no `role`, despite being a full modal | `popover/Popover.vue:141-161` | medium |

---

## 14. What a modernization should REUSE rather than rebuild

1. **`Dialog.vue`'s native `<dialog>` + `showModal()` foundation** (`dialog/Dialog.vue:88-91`). It
   buys the focus trap, top-layer stacking, native Escape and `::backdrop` for free. The two
   stacking guards — `handleDialogClose`'s `e.target === dialogRef.value` check (`:99-101`) and
   `handleClickOutside`'s "am I the last `dialog[open]`" check (`:103-108`) — encode real bugs that
   were already fixed once; keep them.

2. **`TeleportWithDirection.vue`** (28 lines). The single correct answer to "teleported content
   loses `[dir]`". Every new overlay should go through it, and `YearInReviewModal.vue:192` should
   be moved onto it rather than a new shim being written.

3. **`composables/useDropdownPosition.js`** as the one positioner. It already handles RTL align
   flipping (`:35`), fit-aware vertical flipping (`:37-46`, `:79-83`), `maxHeight` derivation
   (`:87`, `:90`), a `SAFE_MARGIN` viewport clamp (`:94-108`), optional container constraint
   (`:52-54`), and both relative and fixed modes. Extending this (and routing `DropdownMenu`'s 41
   consumers through it) is the fix for inconsistency #6, #7 and #8 — a new positioning library is
   not needed.

4. **`SidePanel.vue`'s overlay choreography.** The deliberate deferral of scroll-lock and focus to
   `@after-enter` so they do not cost a frame of the slide (`:56-61`), the `afterLeave` emit for
   `v-if`-mounted consumers (`:27-29`), the `previousActiveElement?.isConnected` focus restore
   (`:43-53`, `:67`), the `dialog[open]` Escape yield (`:76-83`), and the logical-property geometry
   `inset-y-3 end-3` + `rtl:translate-x-[calc(-100%-0.75rem)]` (`:109-122`). Add a focus trap to
   this component; do not write a second drawer.

5. **`Popover.vue`'s responsive switch** (`:40-43`, `:141-161`) is the only existing mobile
   adaptation and the natural seed for any phone treatment of `Dialog`. Its 244-line spec
   (`popover/specs/Popover.spec.js`) already pins the contract — toggling, Escape with nested
   overlays, click-outside, the `md` switch, `disableMobileView`, and the close-on-scroll
   thresholds. Keep that spec green.

6. **The `data-popover-content` / `data-popover-backdrop` / `data-dropdown-menu` attribute
   contract** (`popover/Popover.vue:143,152,168`; `base/DropdownFloating.vue:23`;
   `base/DropdownContainer.vue:26`). Three unrelated surfaces already depend on it to avoid
   closing when a teleported child is clicked (`ConversationSidebar.vue:44-53`,
   `CampaignLayout.vue:35`, `Popover.vue:105-108`). Any new overlay must keep emitting these
   markers or those surfaces regress.

7. **The `ProseMirror-prompt-backdrop` escape hatch.** Four files carry it
   (`Popover.vue:106`, `ConversationSidebar.vue:48`, `CampaignLayout.vue:35`, plus the spec at
   `Popover.spec.js:165`), and `Dialog.vue`/`SidePanel.vue` solve the same case via generic
   `dialog[open]` queries. The editor's link prompt is library-owned markup; it cannot be
   restyled away, so the guard has to survive.

8. **`dropdown-menu/base/*` as the primitive layer.** `provideDropdownContext` / `useDropdownContext`
   (`base/provider.js:3-20`, which throws on a missing parent), `provideDropdownTeleport()` for
   clipping ancestors (`:22-31`), the polymorphic `DropdownItem` (`base/DropdownItem.vue:21-32`)
   with `preserveOpen` (`:12`, `:38`), `getTrigger()` as a getter for swappable triggers
   (`base/DropdownContainer.vue:14-16`), and the documented Chrome stacked-`backdrop-blur`
   workaround in `DropdownBody.vue:17-23` (crbug 40835530). This is the better of the two menu
   systems; converge `DropdownMenu.vue` onto it rather than inventing a third.

9. **`SidePanel`'s and `Dialog`'s `md`/`lg`/`xl`/`2xl`/`3xl` naming.** The token names are already
   shared between the two containers (`dialog/Dialog.vue:54`, `side-panel/SidePanel.vue:19`) and map
   to the same Tailwind `max-w-*` values. Keep the names, fill the gap at the small end (`sm` is
   dead, there is nothing below 448 except the UA cap), and make them responsive — do not renumber.

10. **The existing i18n keys and slot names.** `DIALOG.BUTTONS.CANCEL` / `DIALOG.BUTTONS.CONFIRM`
    (`dashboard/i18n/locale/en/components.json:18-23`), `GENERAL.CLOSE` (`SidePanel.vue:146`),
    `DROPDOWN_MENU.{SEARCH_PLACEHOLDER,SEARCHING,EMPTY_STATE}` (`DropdownMenu.vue:151,293-296`), and
    the slot contracts `#description`/`#footer` on `Dialog`, `#header`/`#header-actions`/`#footer`
    on `SidePanel`, `#content` on `Popover`, and the item-scoped `#thumbnail`/`#icon`/`#label`/
    `#trailing-icon` on `DropdownMenu`. 12 Dialog call sites and 8 SidePanel call sites are wired to
    these names; renaming them is a 63-file change with no user-visible gain.

11. **`defineExpose({ open, close })` as the container contract.** All 63 `Dialog` and 8 `SidePanel`
    call sites drive their container by template ref (`dialog/Dialog.vue:114`,
    `side-panel/SidePanel.vue:89`), and several wrap it in a `watch` on an `open` prop
    (`ConversationUsageDrawer.vue:57-69`, `AssistantDrilldownDrawer.vue:59-71`,
    `ReportDrilldownDrawer.vue`). Switching to `v-model` would touch every one of them.
