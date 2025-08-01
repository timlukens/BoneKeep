/datum/action/cooldown/spell/undirected/shapeshift
	school = SCHOOL_TRANSMUTATION
	charge_required = FALSE

	/// Whehter we revert to our human form on death.
	var/revert_on_death = TRUE
	/// Whether we die when our shapeshifted form is killed
	var/die_with_shapeshifted_form = TRUE
	/// Whether we convert our health from one form to another
	var/convert_damage = TRUE
	/// If convert damage is true, the damage type we deal when converting damage back and forth
	var/convert_damage_type = BRUTE

	/// Our chosen type
	var/mob/living/shapeshift_type
	/// All possible types we can become
	var/list/atom/possible_shapes

/datum/action/cooldown/spell/undirected/shapeshift/is_valid_target(atom/cast_on)
	return isliving(cast_on)

/datum/action/cooldown/spell/undirected/shapeshift/proc/is_shifted(mob/living/cast_on)
	return locate(/obj/shapeshift_holder) in cast_on

/datum/action/cooldown/spell/undirected/shapeshift/before_cast(atom/cast_on)
	. = ..()
	if(. & SPELL_CANCEL_CAST)
		return

	if(shapeshift_type)
		return

	if(length(possible_shapes) == 1)
		shapeshift_type = possible_shapes[1]
		return

	var/list/shape_names_to_types = list()
	var/list/shape_names_to_image = list()
	if(!length(shape_names_to_types) || !length(shape_names_to_image))
		for(var/atom/path as anything in possible_shapes)
			var/shape_name = initial(path.name)
			shape_names_to_types[shape_name] = path
			shape_names_to_image[shape_name] = image(icon = initial(path.icon), icon_state = initial(path.icon_state))

	var/picked_type = show_radial_menu(
		cast_on,
		cast_on,
		shape_names_to_image,
		custom_check = CALLBACK(src, PROC_REF(check_menu), cast_on),
		radius = 38,
	)

	if(!picked_type)
		return . | SPELL_CANCEL_CAST

	var/atom/shift_type = shape_names_to_types[picked_type]
	if(!ispath(shift_type))
		return . | SPELL_CANCEL_CAST

	shapeshift_type = shift_type || pick(possible_shapes)
	if(QDELETED(src) || QDELETED(owner) || !can_cast_spell(feedback = FALSE))
		return . | SPELL_CANCEL_CAST

/datum/action/cooldown/spell/undirected/shapeshift/cast(mob/living/cast_on)
	. = ..()
	cast_on.buckled?.unbuckle_mob(cast_on, force = TRUE)

	// Do the shift back or forth
	if(is_shifted(cast_on))
		restore_form(cast_on)
	else
		do_shapeshift(cast_on)

/datum/action/cooldown/spell/undirected/shapeshift/proc/check_menu(mob/living/caster)
	if(QDELETED(src))
		return FALSE
	if(QDELETED(caster))
		return FALSE

	return !caster.incapacitated()

/datum/action/cooldown/spell/undirected/shapeshift/proc/do_shapeshift(mob/living/caster)
	if(is_shifted(caster))
		to_chat(caster, span_warning("You're already shapeshifted!"))
		CRASH("[type] called do_shapeshift while shapeshifted.")

	var/mob/living/new_shape = new shapeshift_type(caster.loc)
	var/obj/shapeshift_holder/new_shape_holder = new(new_shape, src, caster)

	spell_requirements &= ~(SPELL_REQUIRES_HUMAN|SPELL_REQUIRES_WIZARD_GARB)

	return new_shape_holder

/datum/action/cooldown/spell/undirected/shapeshift/proc/restore_form(mob/living/caster)
	var/obj/shapeshift_holder/current_shift = is_shifted(caster)
	if(QDELETED(current_shift))
		return

	var/mob/living/restored_player = current_shift.stored

	current_shift.restore()
	spell_requirements = initial(spell_requirements) // Miiight mess with admin stuff.

	return restored_player

// Maybe one day, this can be a component or something
// Until then, this is what holds data between wizard and shapeshift form whenever shapeshift is cast.
/obj/shapeshift_holder
	name = "Shapeshift holder"
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | ON_FIRE | UNACIDABLE | ACID_PROOF
	var/mob/living/stored
	var/mob/living/shape
	var/restoring = FALSE
	var/datum/action/cooldown/spell/undirected/shapeshift/source

/obj/shapeshift_holder/Initialize(mapload, datum/action/cooldown/spell/undirected/shapeshift/_source, mob/living/caster)
	. = ..()
	source = _source
	shape = loc
	if(!istype(shape))
		stack_trace("shapeshift holder created outside mob/living")
		return INITIALIZE_HINT_QDEL
	stored = caster
	if(stored.mind)
		stored.mind.transfer_to(shape)
	stored.forceMove(src)
	stored.notransform = TRUE
	if(source.convert_damage)
		var/damage_percent = (stored.maxHealth - stored.health) / stored.maxHealth;
		var/damapply = damage_percent * shape.maxHealth;

		shape.apply_damage(damapply, source.convert_damage_type, forced = TRUE);
		shape.blood_volume = stored.blood_volume;

	RegisterSignal(shape, list(COMSIG_PARENT_QDELETING, COMSIG_LIVING_DEATH), PROC_REF(shape_death))
	RegisterSignal(stored, list(COMSIG_PARENT_QDELETING, COMSIG_LIVING_DEATH), PROC_REF(caster_death))

/obj/shapeshift_holder/Destroy()
	// restore_form manages signal unregistering. If restoring is TRUE, we've already unregistered the signals and we're here
	// because restore() qdel'd src.
	if(!restoring)
		restore()
	stored = null
	shape = null
	return ..()

/obj/shapeshift_holder/Moved()
	. = ..()
	if(!restoring && !QDELETED(src))
		restore()

/obj/shapeshift_holder/handle_atom_del(atom/A)
	if(A == stored && !restoring)
		restore()

/obj/shapeshift_holder/Exited(atom/movable/gone, direction)
	if(stored == gone && !restoring)
		restore()

/obj/shapeshift_holder/proc/caster_death()
	SIGNAL_HANDLER

	//Something kills the stored caster through direct damage.
	if(source.revert_on_death)
		restore(death = TRUE)
	else
		shape.death()

/obj/shapeshift_holder/proc/shape_death()
	SIGNAL_HANDLER

	//Shape dies.
	if(source.die_with_shapeshifted_form)
		if(source.revert_on_death)
			restore(death = TRUE)
	else
		restore()

/obj/shapeshift_holder/proc/restore(death=FALSE)
	// Destroy() calls this proc if it hasn't been called. Unregistering here prevents multiple qdel loops
	// when caster and shape both die at the same time.
	UnregisterSignal(shape, list(COMSIG_PARENT_QDELETING, COMSIG_LIVING_DEATH))
	UnregisterSignal(stored, list(COMSIG_PARENT_QDELETING, COMSIG_LIVING_DEATH))
	restoring = TRUE
	stored.forceMove(shape.loc)
	stored.notransform = FALSE
	if(shape.mind)
		shape.mind.transfer_to(stored)
	if(death)
		stored.death()
	else if(source.convert_damage)
		stored.revive(full_heal = TRUE, admin_revive = FALSE)

		var/damage_percent = (shape.maxHealth - shape.health)/shape.maxHealth;
		var/damapply = stored.maxHealth * damage_percent

		stored.apply_damage(damapply, source.convert_damage_type, forced = TRUE)
	if(source.convert_damage)
		stored.blood_volume = shape.blood_volume;

	// This guard is important because restore() can also be called on COMSIG_PARENT_QDELETING for shape, as well as on death.
	// This can happen in, for example, [/proc/wabbajack] where the mob hit is qdel'd.
	if(!QDELETED(shape))
		QDEL_NULL(shape)

	qdel(src)
	return stored
