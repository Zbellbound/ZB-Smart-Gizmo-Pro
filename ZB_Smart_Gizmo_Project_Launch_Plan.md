# ZB Smart Gizmo Pro – Extension Warehouse Launch Plan

> **Planning document (noted 2026-07-07):** this is a business/go-to-market plan, not a record of
> what's implemented. Any trial/licensing mechanism described below is not present anywhere in the
> current codebase — see `AUDIT_REPORT.md` M5. Treat items here as proposed, not shipped, until
> confirmed against the code.

## Goal

Launch ZB Smart Gizmo Pro as a professional SketchUp workflow extension, not just a small utility.

Position it as:

> A modern all-in-one transform system for SketchUp, combining move, rotate, scale, precision input, pivot editing, and Smart Scale.

---

## 1. Pricing Plan

### Recommended launch price

**$29 USD**

Use this as the early launch price while the extension is still new and does not yet have many reviews or public proof.

### Standard price after traction

**$39–$49 USD**

This means: once the extension has proven demand, reviews, downloads, and real users, raise the price from the launch price.

Recommended path:

| Stage | Price | When |
|---|---:|---|
| Launch | $29 | First release |
| Early traction | $39 | After positive signs |
| Strong traction | $49 | If Smart Scale is clearly valued |

### What “traction” means

You do not need thousands of users before raising the price. Look for a combination of:

- 50–200 downloads
- Several trial users converting to paid
- A few positive reviews
- Low refund / complaint rate
- Users specifically praising Smart Scale, precision input, or the gizmo workflow
- Few serious bug reports
- Users asking for more features instead of asking “what does this do?”

### Suggested rule

Raise from **$29 to $39** when you have:

- at least 3–5 positive user signals
- no major stability issues
- a demo video showing the value clearly

Only test **$49** when Smart Scale becomes the main reason people buy.

---

## 2. Trial Period

### Recommendation

Offer a **14-day full-feature trial**.

This is important because ZB Smart Gizmo Pro is a workflow tool. Users need to try it inside a real project before they understand the value.

### Why not a feature-limited trial?

Avoid locking key features during the trial.

The strongest features are:

- Smart Scale
- numeric input
- pivot editing
- local/global orientation
- all-in-one transform workflow

If users cannot try these, they may think the extension is just another gizmo.

### Best trial setup

Recommended:

- 14-day full-feature trial
- No watermark
- No annoying popups during active modeling
- Gentle reminder near the end of trial
- Clear upgrade path after trial

### Optional after-trial behavior

If technically possible, after the trial expires:

- Keep basic transform gizmo visible
- Lock Smart Scale and advanced numeric input
- Show a simple message explaining what is locked

Example message:

> Your ZB Smart Gizmo Pro trial has ended. Basic transform preview remains available, but Smart Scale and precision input require a license.

This lets the user remember the tool without feeling punished.

---

## 3. Extension Warehouse Notes

Based on public SketchUp / Trimble material:

- Extension Warehouse supports both free and paid extensions.
- Paid extensions can use either one-time purchase or recurring payment models.
- Extensions with a listed price can be purchased in Extension Warehouse.
- Some extensions use a “Listing Page” model where users go to the developer’s site, but since you plan to sell only through Extension Warehouse, keep the purchase flow inside Extension Warehouse if available to you.
- Developers must follow Trimble / SketchUp developer terms and submission requirements.
- SketchUp’s public developer guidance says extensions are reviewed against submission requirements and qualifications before publishing.
- Extension Warehouse has supported fixed-term licensing for developers, including 12-month access licensing.

### Practical recommendation for you

Use:

- Extension Warehouse purchase flow
- Native SketchUp / Extension Warehouse licensing if available
- 14-day trial
- One-time price at launch, unless you specifically want a yearly license

### Pricing model choice

For ZB Smart Gizmo Pro, start with:

**One-time purchase: $29 launch / $39 standard**

Do not start with subscription unless you plan frequent major updates, support, and ongoing Smart Scale improvements.

A yearly license can work later, but a one-time purchase is easier for early trust.

---

## 4. Positioning

### Do not position it as

> A gizmo plugin.

That sounds small and optional.

### Position it as

> A modern transform system for SketchUp.

This sounds like a workflow upgrade.

### Core message

> Move, rotate, and scale in one interactive tool — with exact input, pivot control, and Smart Scale.

### Main customer promise

> Work faster without losing precision.

### Smart Scale promise

> Resize supported objects while preserving their structure whenever possible.

Avoid overpromising. Do not say it works perfectly on every model. Say it works best on structured groups, components, frames, windows, furniture, and similar objects.

---

## 5. Competitor Positioning

### Native SketchUp tools

Native SketchUp already has Move, Rotate, and Scale, so users may ask why they need this.

Your answer:

- One tool instead of switching between tools
- Viewport handles for direct control
- Exact input directly in the workflow
- Pivot editing
- Local/global orientation
- Smart Scale for structure-aware resizing

### FredoScale / Fredo6 ecosystem

FredoScale is a known advanced scaling tool in the SketchUp world.

Your differentiation:

- Cleaner all-in-one transform workflow
- Modern viewport gizmo
- Move + rotate + scale in one system
- Smart Scale is designed around preserving structure in supported objects
- Less “toolbox complexity,” more direct interaction

### Basic transform helpers

Your differentiation:

- Not just move/rotate/scale helpers
- Includes exact numeric workflows
- Includes pivot editing
- Includes orientation modes
- Includes Smart Scale

---

## 6. Extension Warehouse Listing Text

### Title

**ZB Smart Gizmo Pro – All-in-One Transform Tool with Smart Scale**

### Short description

Move, rotate, and scale with one modern viewport gizmo. Includes exact input, pivot editing, local/global orientation, and Smart Scale for supported objects.

### Full description

**ZB Smart Gizmo Pro is a modern transform system for SketchUp.**

Instead of switching between separate Move, Rotate, and Scale tools, ZB Smart Gizmo Pro gives you one interactive viewport gizmo for fast, precise modeling.

Drag directly in the viewport when you want speed. Enter exact values when you need precision.

ZB Smart Gizmo Pro includes:

- Move, rotate, and scale from one gizmo
- Exact numeric input for precise transformations
- Axis-based move controls
- Rotate rings with exact angle input
- Scale handles with target-length style input
- Relative scale expressions such as `+100`, `600+100`, and `24in+2in`
- Pivot editing
- Global and object/local orientation modes
- Plane move handles for XY, YZ, and XZ movement
- Optional arrow-key rotate shortcuts
- Built-in preferences
- Built-in manual

### Smart Scale

Smart Scale is a structure-aware scaling mode for supported objects.

Instead of simply stretching everything, Smart Scale tries to preserve important object structure, such as detailed ends, corners, and repeated parts, while resizing the middle span where possible.

Smart Scale is especially useful for:

- frames
- windows
- tables
- furniture parts
- nested groups and components
- structured assemblies

Smart Scale works best on well-structured groups and components. Simple plain geometry may fall back to a simpler scaling behavior.

### Why use it?

ZB Smart Gizmo Pro is designed for modelers who want a faster transform workflow without giving up precision.

Use it when you want:

- fewer tool switches
- cleaner viewport interaction
- exact typed values
- better pivot control
- smarter resizing of structured objects

### Suggested closing line

**Transform faster. Stay precise. Resize smarter.**

---

## 7. Screenshots Needed

Prepare 5–7 screenshots.

### Screenshot 1: Main gizmo

Show selected object with the full gizmo visible.

Caption:

> Move, rotate, and scale from one interactive viewport gizmo.

### Screenshot 2: Numeric move input

Show the move dialog.

Caption:

> Drag freely or enter exact movement values.

### Screenshot 3: Rotation input

Show rotate ring + angle input.

Caption:

> Rotate visually or type an exact angle.

### Screenshot 4: Scale input

Show target-length / expression input.

Caption:

> Scale precisely with target values and relative expressions.

### Screenshot 5: Smart Scale before/after

Show native scale damaging an object vs Smart Scale preserving structure.

Caption:

> Smart Scale helps preserve supported object structures while resizing.

### Screenshot 6: Pivot editing

Show pivot moved away from center.

Caption:

> Edit the transform pivot directly in the viewport.

### Screenshot 7: Local/global orientation

Show gizmo aligned to object axes.

Caption:

> Switch between global and object/local orientation.

---

## 8. Demo Video Plan

### Length

**30–60 seconds**

Do not make it too long. The goal is fast understanding.

### Demo video structure

#### 0–5 seconds: Hook

Show the problem:

- SketchUp native Move / Rotate / Scale requires switching tools
- Native Scale stretches objects poorly

Text on screen:

> Transform faster in SketchUp.

#### 5–15 seconds: All-in-one gizmo

Show:

- select object
- move using arrow
- rotate using ring
- scale using handle

Text on screen:

> Move, rotate, and scale from one gizmo.

#### 15–25 seconds: Precision input

Show:

- click axis
- type exact move distance
- click rotate ring
- type angle
- click scale handle
- type target value

Text on screen:

> Drag freely. Type exact values.

#### 25–45 seconds: Smart Scale

This is the money shot.

Show side-by-side:

- Native Scale stretches a frame/window/table badly
- Smart Scale preserves ends/corners and stretches the middle span

Text on screen:

> Smart Scale resizes supported objects without simply stretching everything.

#### 45–55 seconds: Pivot and orientation

Show:

- move pivot
- switch local/global orientation

Text on screen:

> Control the pivot. Work in global or local orientation.

#### 55–60 seconds: Closing

Text on screen:

> ZB Smart Gizmo Pro  
> Transform faster. Stay precise. Resize smarter.

---

## 9. Demo Video Script

### Voiceover version

> Meet ZB Smart Gizmo Pro — a modern transform system for SketchUp.
>
> Instead of switching between Move, Rotate, and Scale, use one interactive gizmo directly in the viewport.
>
> Drag when you want speed, or type exact values when you need precision.
>
> Rotate by dragging the rings or entering an exact angle.
>
> Scale visually, enter target lengths, or use relative expressions.
>
> With Smart Scale, supported objects like frames, windows, tables, and structured components can be resized while preserving important details.
>
> You can also edit the pivot and switch between global and local orientation.
>
> ZB Smart Gizmo Pro: transform faster, stay precise, resize smarter.

### No-voiceover text-only version

Use short text overlays:

1. Move, rotate, and scale from one gizmo
2. Drag freely in the viewport
3. Type exact values anytime
4. Smart Scale preserves supported structures
5. Edit the pivot
6. Use global or local orientation
7. Transform faster. Stay precise. Resize smarter.

---

## 10. Launch Checklist

### Before submitting

- Test in multiple SketchUp versions you intend to support
- Test on Windows and Mac if possible
- Test with groups
- Test with components
- Test with copied components
- Test Dynamic Component behavior carefully
- Test nested group/component structures
- Test model files from older SketchUp versions
- Test trial expiration
- Test license activation
- Test uninstall/reinstall behavior
- Prepare screenshots
- Prepare demo video
- Prepare clean description text
- Prepare support email / support page
- Prepare changelog
- Prepare privacy policy if required
- Prepare EULA if you use your own instead of the general Extension Warehouse EULA

### Listing assets

- Icon
- Main screenshot
- 5–7 screenshots
- Demo video
- Short description
- Full description
- Version number
- Compatibility info
- Support contact
- Website link
- Manual / help page

### Launch day

- Publish at $29
- Enable trial
- Check listing formatting
- Install from Extension Warehouse as a normal user
- Verify license flow
- Verify trial flow
- Verify demo video link
- Verify screenshots
- Monitor support email

---

## 11. Post-Launch Plan

### First 2 weeks

Focus on stability.

- Fix bugs quickly
- Respond politely to support requests
- Track repeated confusion
- Improve manual if users ask the same question more than twice
- Ask happy users for reviews

### After first traction

Raise price from **$29 to $39** when:

- trial users are converting
- reviews are positive
- bugs are under control
- Smart Scale is clearly understood

### Later

Consider **$49** when:

- Smart Scale is strong and reliable
- demo video clearly proves value
- users compare it favorably to other advanced SketchUp workflow tools
- support burden is manageable

---

## 12. Feature Messaging Cheat Sheet

### Best feature names to emphasize

- All-in-one transform gizmo
- Smart Scale
- Exact numeric input
- Pivot editing
- Local/global orientation
- Plane move handles
- Native SketchUp tool compatibility

### Best short marketing lines

- Transform faster. Stay precise. Resize smarter.
- Move, rotate, and scale without switching tools.
- Drag freely or enter exact values.
- Smart Scale for supported structured objects.
- A modern transform workflow for SketchUp.

### Avoid saying

- Works perfectly on all models
- Replaces every SketchUp transform tool
- Fully parametric
- Automatically understands every object
- Guaranteed structure preservation

Use honest wording. Smart Scale is powerful, but it should be presented as “structure-aware for supported objects,” not magic.

---

## 13. Final Recommendation

Launch with:

- **14-day full-feature trial**
- **$29 launch price**
- **$39 standard price after early traction**
- **Possible $49 price later if Smart Scale becomes the main selling point**
- **30–60 second demo video**
- **Strong before/after Smart Scale comparison**
- **Extension Warehouse-only sales flow**

Most important sales message:

> ZB Smart Gizmo Pro is not just a gizmo. It is a faster, more precise transform workflow for SketchUp.
