//// MS13 Agriculture Using Stripped Down & Modified TG Botany ////

#define IS_SHARP_AXE	3
#define SOIL_EDGE_LAYER 2.95

/obj/machinery/ms13/agriculture
	name = "dirt crate"
	icon = 'mojave/icons/hydroponics/soil.dmi'
	icon_state = "crate_full"
	density = TRUE
	pass_flags_self = PASSMACHINE | LETPASSTHROW
	flags_1 = NODECONSTRUCT_1
	obj_flags = CAN_BE_HIT | UNIQUE_RENAME
	circuit = null
	use_power = NO_POWER_USE
	///The amount of water in the tray (max 100)
	var/waterlevel = 100
	///The maximum amount of water in the tray
	var/maxwater = 100
	///How many units of nutrients will be drained in the tray.
	var/nutridrain = 1
	///The maximum nutrient reagent container size of the tray.
	var/maxnutri = 20
	///The amount of pests in the tray (max 10)
	var/pestlevel = 0
	///The amount of weeds in the tray (max 10)
	var/weedlevel = 0
	///Nutriment's effect on yield
	var/yieldmod = 1
	///Nutriment's effect on mutations
	var/mutmod = 1
	///Toxicity in the tray?
	var/toxic = 0
	///Current age
	var/age = 0
	///The status of the plant in the tray. Whether it's harvestable, alive, missing or dead.
	var/plant_status = HYDROTRAY_NO_PLANT
	///Its health
	var/plant_health
	///Last time it was harvested
	var/lastproduce = 0
	///Used for timing of cycles.
	var/lastcycle = 0
	///About 10 seconds / cycle
	var/cycledelay = 200
	///The currently planted seed
	var/obj/item/seeds/myseed
	///Obtained from the quality of the parts used in the tray, determines nutrient drain rate.
	var/rating = 1
	///Can it be unwrenched to move?
	var/unwrenchable = TRUE
	///Have we been visited by a bee recently, so bees dont overpollinate one plant
	var/recent_bee_visit = FALSE
	///The last user to add a reagent to the tray, mostly for logging purposes.
	var/datum/weakref/lastuser
	///If the tray generates nutrients and water on its own
	var/self_sustaining = FALSE

/obj/machinery/ms13/agriculture/Initialize(mapload)
	//ALRIGHT YOU DEGENERATES. YOU HAD REAGENT HOLDERS FOR AT LEAST 4 YEARS AND NONE OF YOU MADE HYDROPONICS TRAYS HOLD NUTRIENT CHEMS INSTEAD OF USING "Points".
	//SO HERE LIES THE "nutrilevel" VAR. IT'S DEAD AND I PUT IT OUT OF IT'S MISERY. USE "reagents" INSTEAD. ~ArcaneMusic, accept no substitutes.
	create_reagents(maxnutri)
	reagents.add_reagent(/datum/reagent/plantnutriment/eznutriment, 10) //Half filled nutrient trays for dirt trays to have more to grow with in prison/lavaland.
	. = ..()

	var/static/list/hovering_item_typechecks = list(
		/obj/item/plant_analyzer = list(
			SCREENTIP_CONTEXT_LMB = "Scan tray stats",
			SCREENTIP_CONTEXT_RMB = "Scan tray chemicals"
		),
		/obj/item/cultivator = list(
			SCREENTIP_CONTEXT_LMB = "Remove weeds",
		),
		/obj/item/shovel = list(
			SCREENTIP_CONTEXT_LMB = "Clear tray",
		),
	)

	AddElement(/datum/element/contextual_screentip_item_typechecks, hovering_item_typechecks)
	register_context()

/obj/machinery/ms13/agriculture/add_context(
	atom/source,
	list/context,
	obj/item/held_item,
	mob/living/user,
)

	// If we don't have a seed, we can't do much.

	// The only option is to plant a new seed.
	if(!myseed)
		if(istype(held_item, /obj/item/seeds))
			context[SCREENTIP_CONTEXT_LMB] = "Plant seed"
			return CONTEXTUAL_SCREENTIP_SET
		return NONE

	// If we DO have a seed, we can do a few things!

	// With a hand we can harvest or remove dead plants
	// If the plant's not in either state, we can't do much else, so early return.
	if(isnull(held_item))
		// Silicons can't interact with trays :frown:
		if(issilicon(user))
			return NONE

		switch(plant_status)
			if(HYDROTRAY_PLANT_DEAD)
				context[SCREENTIP_CONTEXT_LMB] = "Remove dead plant"
				return CONTEXTUAL_SCREENTIP_SET

			if(HYDROTRAY_PLANT_HARVESTABLE)
				context[SCREENTIP_CONTEXT_LMB] = "Harvest plant"
				return CONTEXTUAL_SCREENTIP_SET

		return NONE

	// If the plant is harvestable, we can graft it with secateurs or harvest it with a plant bag.
	if(plant_status == HYDROTRAY_PLANT_HARVESTABLE)
		if(istype(held_item, /obj/item/secateurs))
			context[SCREENTIP_CONTEXT_LMB] = "Graft plant"
			return CONTEXTUAL_SCREENTIP_SET

		if(istype(held_item, /obj/item/storage/bag/plants))
			context[SCREENTIP_CONTEXT_LMB] = "Harvest plant"
			return CONTEXTUAL_SCREENTIP_SET

	// Edibles and pills can be composted.
	if(IS_EDIBLE(held_item) || istype(held_item, /obj/item/reagent_containers/pill))
		context[SCREENTIP_CONTEXT_LMB] = "Compost"
		return CONTEXTUAL_SCREENTIP_SET

	// Aand if a reagent container has water or plant fertilizer in it, we can use it on the plant.
	if(is_reagent_container(held_item) && length(held_item.reagents.reagent_list))
		var/datum/reagent/most_common_reagent = held_item.reagents.get_master_reagent()
		context[SCREENTIP_CONTEXT_LMB] = "[istype(most_common_reagent, /datum/reagent/water) ? "Water" : "Feed"] plant"
		return CONTEXTUAL_SCREENTIP_SET

	return NONE

/obj/machinery/ms13/agriculture/Destroy()
	if(myseed)
		QDEL_NULL(myseed)
	return ..()

/obj/machinery/ms13/agriculture/Exited(atom/movable/gone)
	. = ..()
	if(!QDELETED(src) && gone == myseed)
		set_seed(null, FALSE)

/obj/machinery/ms13/agriculture/process(delta_time)
	var/needs_update = 0 // Checks if the icon needs updating so we don't redraw empty trays every time

	if(self_sustaining)
		if(powered())
			adjust_waterlevel(rand(1,2) * delta_time * 0.5)
			adjust_weedlevel(-0.5 * delta_time)
			adjust_pestlevel(-0.5 * delta_time)
		else
			set_self_sustaining(FALSE)
			visible_message(span_warning("[name]'s auto-grow functionality shuts off!"))

	if(world.time > (lastcycle + cycledelay))
		lastcycle = world.time
		if(myseed && plant_status != HYDROTRAY_PLANT_DEAD)
			// Advance age
			age++
			if(age < myseed.maturation)
				lastproduce = age

			needs_update = 1


//Nutrients//////////////////////////////////////////////////////////////
			// Nutrients deplete at a constant rate, since new nutrients can boost stats far easier.
			apply_chemicals(lastuser?.resolve())
			if(self_sustaining)
				reagents.remove_any(min(0.5, nutridrain))
			else
				reagents.remove_any(nutridrain)

			// Lack of nutrients hurts non-weeds
			if(reagents.total_volume <= 0 && !myseed.get_gene(/datum/plant_gene/trait/plant_type/weed_hardy))
				adjust_plant_health(-rand(1,3))

//Photosynthesis/////////////////////////////////////////////////////////
			// Lack of light hurts non-mushrooms
			if(isturf(loc))
				var/turf/currentTurf = loc
				var/lightAmt = currentTurf.get_lumcount()
				var/is_fungus = myseed.get_gene(/datum/plant_gene/trait/plant_type/fungal_metabolism)
				if(lightAmt < (is_fungus ? 0.2 : 0.4))
					adjust_plant_health((is_fungus ? -1 : -2) / rating)

//Water//////////////////////////////////////////////////////////////////
			// Drink random amount of water
			adjust_waterlevel(-rand(1,6) / rating)

			// If the plant is dry, it loses health pretty fast, unless mushroom
			if(waterlevel <= 10 && !myseed.get_gene(/datum/plant_gene/trait/plant_type/fungal_metabolism))
				adjust_plant_health(-rand(0,1) / rating)
				if(waterlevel <= 0)
					adjust_plant_health(-rand(0,2) / rating)

			// Sufficient water level and nutrient level = plant healthy but also spawns weeds
			else if(waterlevel > 10 && reagents.total_volume > 0)
				adjust_plant_health(rand(1,2) / rating)
				if(myseed && prob(myseed.weed_chance))
					adjust_weedlevel(myseed.weed_rate)
				else if(prob(5))  //5 percent chance the weed population will increase
					adjust_weedlevel(1 / rating)

//Toxins/////////////////////////////////////////////////////////////////

			// Too much toxins cause harm, but when the plant drinks the contaiminated water, the toxins disappear slowly
			if(toxic >= 40 && toxic < 80)
				adjust_plant_health(-1 / rating)
				adjust_toxic(-rating * 2)
			else if(toxic >= 80) // I don't think it ever gets here tbh unless above is commented out
				adjust_plant_health(-3)
				adjust_toxic(-rating * 3)

//Pests & Weeds//////////////////////////////////////////////////////////

			if(pestlevel >= 8)
				if(!myseed.get_gene(/datum/plant_gene/trait/carnivory))
					if(myseed.potency >=30)
						myseed.adjust_potency(-rand(2,6)) //Pests eat leaves and nibble on fruit, lowering potency.
						myseed.set_potency(min((myseed.potency), CARNIVORY_POTENCY_MIN, MAX_PLANT_POTENCY))
				else
					adjust_plant_health(2 / rating)
					adjust_pestlevel(-1 / rating)

			else if(pestlevel >= 4)
				if(!myseed.get_gene(/datum/plant_gene/trait/carnivory))
					if(myseed.potency >=30)
						myseed.adjust_potency(-rand(1,4))
						myseed.set_potency(min((myseed.potency), CARNIVORY_POTENCY_MIN, MAX_PLANT_POTENCY))

				else
					adjust_plant_health(1 / rating)
					if(prob(50))
						adjust_pestlevel(-1 / rating)

			else if(pestlevel < 4 && myseed.get_gene(/datum/plant_gene/trait/carnivory))
				if(prob(5))
					adjust_pestlevel(-1 / rating)

			// If it's a weed, it doesn't stunt the growth
			if(weedlevel >= 5 && !myseed.get_gene(/datum/plant_gene/trait/plant_type/weed_hardy))
				if(myseed.yield >=3)
					myseed.adjust_yield(-rand(1,2)) //Weeds choke out the plant's ability to bear more fruit.
					myseed.set_yield(min((myseed.yield), WEED_HARDY_YIELD_MIN, MAX_PLANT_YIELD))

//This is the part with pollination
			pollinate()

//This is where stability mutations exist now.
			if(myseed.instability >= 80)
				var/mutation_chance = myseed.instability - 75
				mutate(0, 0, 0, 0, 0, 0, 0, mutation_chance, 0) //Scaling odds of a random trait or chemical
			if(myseed.instability >= 60)
				if(prob((myseed.instability)/2) && !self_sustaining && LAZYLEN(myseed.mutatelist)) //Minimum 30%, Maximum 50% chance of mutating every age tick when not on autogrow.
					mutatespecie()
					myseed.set_instability(myseed.instability/2)
			if(myseed.instability >= 40)
				if(prob(myseed.instability))
					hardmutate()
			if(myseed.instability >= 20 )
				if(prob(myseed.instability))
					mutate()

//Health & Age///////////////////////////////////////////////////////////

			// Plant dies if plant_health <= 0
			if(plant_health <= 0)
				plantdies()
				adjust_weedlevel(1 / rating) // Weeds flourish

			// If the plant is too old, lose health fast
			if(age > myseed.lifespan)
				adjust_plant_health(-rand(1,5) / rating)

			// Harvest code
			if(age > myseed.production && (age - lastproduce) > myseed.production && plant_status == HYDROTRAY_PLANT_GROWING)
				if(myseed && myseed.yield != -1) // Unharvestable shouldn't be harvested
					set_plant_status(HYDROTRAY_PLANT_HARVESTABLE)
				else
					lastproduce = age
			if(prob(5))  // On each tick, there's a 5 percent chance the pest population will increase
				adjust_pestlevel(1 / rating)
		else
			if(waterlevel > 10 && reagents.total_volume > 0 && prob(10))  // If there's no plant, the percentage chance is 10%
				adjust_weedlevel(1 / rating)

		// Weeeeeeeeeeeeeeedddssss
		if(weedlevel >= 10 && prob(50) && !self_sustaining) // At this point the plant is kind of fucked. Weeds can overtake the plant spot.
			if(myseed && myseed.yield >= 3)
				myseed.adjust_yield(-rand(1,2)) //Loses even more yield per tick, quickly dropping to 3 minimum.
				myseed.set_yield(min((myseed.yield), WEED_HARDY_YIELD_MIN, MAX_PLANT_YIELD))
			if(!myseed)
				weedinvasion()
			needs_update = 1
		if (needs_update)
			update_appearance()

		if(myseed)
			SEND_SIGNAL(myseed, COMSIG_SEED_ON_GROW, src)

	return

/obj/machinery/ms13/agriculture/update_appearance(updates)
	. = ..()
	if(self_sustaining)
		set_light(3)
		return
	if(myseed?.get_gene(/datum/plant_gene/trait/glow)) // Hydroponics needs a refactor, badly.
		var/datum/plant_gene/trait/glow/G = myseed.get_gene(/datum/plant_gene/trait/glow)
		set_light(G.glow_range(myseed), G.glow_power(myseed), G.glow_color)
		return
	set_light(0)

/obj/machinery/ms13/agriculture/update_overlays()
	. = ..()
	if(myseed)
		. += update_plant_overlay()

/obj/machinery/ms13/agriculture/proc/update_plant_overlay()
	var/mutable_appearance/plant_overlay = mutable_appearance(myseed.growing_icon, layer = OBJ_LAYER + 0.01)
	switch(plant_status)
		if(HYDROTRAY_PLANT_DEAD)
			plant_overlay.icon_state = myseed.icon_dead
		if(HYDROTRAY_PLANT_HARVESTABLE)
			if(!myseed.icon_harvest)
				plant_overlay.icon_state = "[myseed.icon_grow][myseed.growthstages]"
			else
				plant_overlay.icon_state = myseed.icon_harvest
		else
			var/t_growthstate = clamp(round((age / myseed.maturation) * myseed.growthstages), 1, myseed.growthstages)
			plant_overlay.icon_state = "[myseed.icon_grow][t_growthstate]"
	return plant_overlay

/obj/machinery/ms13/agriculture/proc/apply_chemicals(mob/user)
	///Contains the reagents within the tray.
	if(myseed)
		myseed.on_chem_reaction(reagents) //In case seeds have some special interactions with special chems, currently only used by vines
	for(var/c in reagents.reagent_list)
		var/datum/reagent/chem = c
		chem.on_hydroponics_apply(myseed, reagents, src, user)

///Sets a new value for the myseed variable, which is the seed of the plant that's growing inside the tray.
/obj/machinery/ms13/agriculture/proc/set_seed(obj/item/seeds/new_seed, delete_old_seed = TRUE)
	var/old_seed = myseed
	myseed = new_seed
	if(old_seed && delete_old_seed)
		qdel(old_seed)
	set_plant_status(new_seed ? HYDROTRAY_PLANT_GROWING : HYDROTRAY_NO_PLANT) //To make sure they can't just put in another seed and insta-harvest it
	if(myseed && myseed.loc != src)
		myseed.forceMove(src)
	SEND_SIGNAL(src, COMSIG_HYDROTRAY_SET_SEED, new_seed)
	update_appearance()

/*
 * Setter proc to set a tray to a new self_sustaining state and update all values associated with it.
 *
 * new_value - true / false value that self_sustaining is being set to
 */
/obj/machinery/ms13/agriculture/proc/set_self_sustaining(new_value)
	if(self_sustaining == new_value)
		return

	self_sustaining = new_value

	update_use_power(self_sustaining ? IDLE_POWER_USE : NO_POWER_USE)
	update_appearance()

	SEND_SIGNAL(src, COMSIG_HYDROTRAY_SET_SELFSUSTAINING, new_value)

/obj/machinery/ms13/agriculture/proc/set_weedlevel(new_weedlevel, update_icon = TRUE)
	if(weedlevel == new_weedlevel)
		return
	SEND_SIGNAL(src, COMSIG_HYDROTRAY_SET_WEEDLEVEL, new_weedlevel)
	weedlevel = new_weedlevel
	if(update_icon)
		update_appearance()

/obj/machinery/ms13/agriculture/proc/set_pestlevel(new_pestlevel, update_icon = TRUE)
	if(pestlevel == new_pestlevel)
		return
	SEND_SIGNAL(src, COMSIG_HYDROTRAY_SET_PESTLEVEL, new_pestlevel)
	pestlevel = new_pestlevel
	if(update_icon)
		update_appearance()

/obj/machinery/ms13/agriculture/proc/set_waterlevel(new_waterlevel, update_icon = TRUE)
	if(waterlevel == new_waterlevel)
		return
	SEND_SIGNAL(src, COMSIG_HYDROTRAY_SET_WATERLEVEL, new_waterlevel)
	waterlevel = new_waterlevel
	if(update_icon)
		update_appearance()

	var/difference = new_waterlevel - waterlevel
	if(difference > 0)
		adjust_toxic(-round(difference/4))//Toxicity dilutation code. The more water you put in, the lesser the toxin concentration.

/obj/machinery/ms13/agriculture/proc/set_plant_health(new_plant_health, update_icon = TRUE, forced = FALSE)
	if(plant_health == new_plant_health || ((!myseed || plant_status == HYDROTRAY_PLANT_DEAD) && !forced))
		return
	SEND_SIGNAL(src, COMSIG_HYDROTRAY_SET_PLANT_HEALTH, new_plant_health)
	plant_health = new_plant_health
	if(update_icon)
		update_appearance()

/obj/machinery/ms13/agriculture/proc/set_toxic(new_toxic, update_icon = TRUE)
	if(toxic == new_toxic)
		return
	SEND_SIGNAL(src, COMSIG_HYDROTRAY_SET_TOXIC, new_toxic)
	toxic = new_toxic
	if(update_icon)
		update_appearance()

/obj/machinery/ms13/agriculture/proc/set_plant_status(new_plant_status)
	if(plant_status == new_plant_status)
		return
	SEND_SIGNAL(src, COMSIG_HYDROTRAY_SET_PLANT_STATUS, new_plant_status)
	plant_status = new_plant_status

// The following procs adjust the hydroponics tray variables, and make sure that the stat doesn't go out of bounds.

/**
 * Adjust water.
 * Raises or lowers tray water values by a set value. Adding water will dillute toxicity from the tray.
 * * adjustamt - determines how much water the tray will be adjusted upwards or downwards.
 */
/obj/machinery/ms13/agriculture/proc/adjust_waterlevel(amt)
	set_waterlevel(clamp(waterlevel + amt, 0, maxwater), FALSE)

/**
 * Adjust Health.
 * Raises the tray's plant_health stat by a given amount, with total health determined by the seed's endurance.
 * * adjustamt - Determines how much the plant_health will be adjusted upwards or downwards.
 */
/obj/machinery/ms13/agriculture/proc/adjust_plant_health(amt)
	set_plant_health(clamp(plant_health + amt, 0, myseed?.endurance), FALSE)

/**
 * Adjust toxicity.
 * Raises the plant's toxic stat by a given amount.
 * * adjustamt - Determines how much the toxic will be adjusted upwards or downwards.
 */
/obj/machinery/ms13/agriculture/proc/adjust_toxic(amt)
	set_toxic(clamp(toxic + amt, 0, MAX_TRAY_TOXINS), FALSE)

/**
 * Adjust Pests.
 * Raises the tray's pest level stat by a given amount.
 * * adjustamt - Determines how much the pest level will be adjusted upwards or downwards.
 */
/obj/machinery/ms13/agriculture/proc/adjust_pestlevel(amt)
	set_pestlevel(clamp(pestlevel + amt, 0, MAX_TRAY_PESTS), FALSE)


/**
 * Adjust Weeds.
 * Raises the plant's weed level stat by a given amount.
 * * adjustamt - Determines how much the weed level will be adjusted upwards or downwards.
 */
/obj/machinery/ms13/agriculture/proc/adjust_weedlevel (amt)
	set_weedlevel(clamp(weedlevel + amt, 0, MAX_TRAY_WEEDS), FALSE)

/obj/machinery/ms13/agriculture/examine(user)
	. = ..()
	if(myseed)
		. += span_info("It has [span_name("[myseed.plantname]")] planted.")
		if (plant_status == HYDROTRAY_PLANT_DEAD)
			. += span_warning("It's dead!")
		else if (plant_status == HYDROTRAY_PLANT_HARVESTABLE)
			. += span_info("It's ready to harvest.")
		else if (plant_health <= (myseed.endurance / 2))
			. += span_warning("It looks unhealthy.")
	else
		. += span_info("It's empty.")

	. += span_info("Water: [waterlevel]/[maxwater].")
	. += span_info("Nutrient: [reagents.total_volume]/[maxnutri].")
	if(self_sustaining)
		. += span_info("The tray's autogrow is active, protecting it from species mutations, weeds, and pests.")

	if(weedlevel >= 5)
		. += span_warning("It's filled with weeds!")
	if(pestlevel >= 5)
		. += span_warning("It's filled with tiny worms!")

/**
 * What happens when a tray's weeds grow too large.
 * Plants a new weed in an empty tray, then resets the tray.
 */
/obj/machinery/ms13/agriculture/proc/weedinvasion()
	var/oldPlantName
	if(myseed) // In case there's nothing in the tray beforehand
		oldPlantName = myseed.plantname
	else
		oldPlantName = "empty tray"
	var/obj/item/seeds/new_seed
	switch(rand(1,18)) // randomly pick predominative weed
		if(16 to 18)
			new_seed = new /obj/item/seeds/ms13/nara(src)
		if(14 to 15)
			new_seed = new /obj/item/seeds/ms13/lureweed(src)
		if(12 to 13)
			new_seed = new /obj/item/seeds/ms13/thistle(src)
		if(10 to 11)
			new_seed = new /obj/item/seeds/ms13/blight(src)
		if(8 to 9)
			new_seed = new /obj/item/seeds/ms13/firecap(src)
		if(6 to 7)
			new_seed = new /obj/item/seeds/ms13/ashblossom(src)
		if(4 to 5)
			new_seed = new /obj/item/seeds/ms13/aster(src)
		else
			new_seed = new /obj/item/seeds/ms13/coyote(src)
	set_seed(new_seed)
	age = 0
	lastcycle = world.time
	set_plant_health(myseed.endurance, update_icon = FALSE)
	set_weedlevel(0, update_icon = FALSE) // Reset
	set_pestlevel(0) // Reset
	visible_message(span_warning("The [oldPlantName] is overtaken by some [myseed.plantname]!"))
	TRAY_NAME_UPDATE

/obj/machinery/ms13/agriculture/proc/mutate(lifemut = 2, endmut = 5, productmut = 1, yieldmut = 2, potmut = 25, wrmut = 2, wcmut = 5, traitmut = 0, stabmut = 3) // Mutates the current seed
	if(!myseed)
		return
	myseed.mutate(lifemut, endmut, productmut, yieldmut, potmut, wrmut, wcmut, traitmut, stabmut)

/obj/machinery/ms13/agriculture/proc/hardmutate()
	mutate(4, 10, 2, 4, 50, 4, 10, 0, 4)


/obj/machinery/ms13/agriculture/proc/mutatespecie() // Mutagent produced a new plant!
	if(!myseed || plant_status == HYDROTRAY_PLANT_DEAD || !LAZYLEN(myseed.mutatelist))
		return

	var/oldPlantName = myseed.plantname
	var/mutantseed = pick(myseed.mutatelist)
	set_seed(new mutantseed(src))

	hardmutate()
	age = 0
	set_plant_health(myseed.endurance, update_icon = FALSE)
	lastcycle = world.time
	set_weedlevel(0, update_icon = FALSE)

	var/message = span_warning("[oldPlantName] suddenly mutates into [myseed.plantname]!")
	addtimer(CALLBACK(src, .proc/after_mutation, message), 0.5 SECONDS)

/**
 * Called after plant mutation, update the appearance of the tray content and send a visible_message()
 */
/obj/machinery/ms13/agriculture/proc/after_mutation(message)
		update_appearance()
		visible_message(message)
		TRAY_NAME_UPDATE
/**
 * Plant Death Proc.
 * Cleans up various stats for the plant upon death, including pests, harvestability, and plant health.
 */
/obj/machinery/ms13/agriculture/proc/plantdies()
	set_plant_health(0, update_icon = FALSE, forced = TRUE)
	set_plant_status(HYDROTRAY_PLANT_DEAD)
	set_pestlevel(0, update_icon = FALSE) // Pests die
	lastproduce = 0
	update_appearance()
	SEND_SIGNAL(src, COMSIG_HYDROTRAY_PLANT_DEATH)

/**
 * Plant Cross-Pollination.
 * Checks all plants in the tray's oview range, then averages out the seed's potency, instability, and yield values.
 * If the seed's instability is >= 20, the seed donates one of it's reagents to that nearby plant.
 * * Range - The Oview range of trays to which to look for plants to donate reagents.
 */
/obj/machinery/ms13/agriculture/proc/pollinate(range = 1)
	for(var/obj/machinery/ms13/agriculture/T in oview(src, range))
		//Here is where we check for window blocking.
		if(!Adjacent(T) && range <= 1)
			continue
		if(T.myseed && T.plant_status != HYDROTRAY_PLANT_DEAD)
			T.myseed.set_potency(round((T.myseed.potency+(1/10)*(myseed.potency-T.myseed.potency))))
			T.myseed.set_instability(round((T.myseed.instability+(1/10)*(myseed.instability-T.myseed.instability))))
			T.myseed.set_yield(round((T.myseed.yield+(1/2)*(myseed.yield-T.myseed.yield))))
			if(myseed.instability >= 20 && prob(70) && length(T.myseed.reagents_add))
				var/list/datum/plant_gene/reagent/possible_reagents = list()
				for(var/datum/plant_gene/reagent/reag in T.myseed.genes)
					possible_reagents += reag
				var/datum/plant_gene/reagent/reagent_gene = pick(possible_reagents) //Let this serve as a lession to delete your WIP comments before merge.
				if(reagent_gene.can_add(myseed))
					if(!reagent_gene.try_upgrade_gene(myseed))
						myseed.genes += reagent_gene.Copy()
					myseed.reagents_from_genes()
					continue

/obj/machinery/ms13/agriculture/attackby(obj/item/O, mob/user, params)
	//Called when mob user "attacks" it with object O
	if(IS_EDIBLE(O) || istype(O, /obj/item/reagent_containers))  // Syringe stuff (and other reagent containers now too)
		var/obj/item/reagent_containers/reagent_source = O

		if(!reagent_source.reagents.total_volume)
			to_chat(user, span_warning("[reagent_source] is empty!"))
			return 1

		if(reagents.total_volume >= reagents.maximum_volume && !reagent_source.reagents.has_reagent(/datum/reagent/water, 1))
			to_chat(user, span_notice("[src] is full."))
			return

		var/list/trays = list(src)//makes the list just this in cases of syringes and compost etc
		var/target = myseed ? myseed.plantname : src
		var/visi_msg = ""
		var/transfer_amount

		if(IS_EDIBLE(reagent_source) || istype(reagent_source, /obj/item/reagent_containers/pill))
			visi_msg="[user] composts [reagent_source], spreading it through [target]"
			transfer_amount = reagent_source.reagents.total_volume
			SEND_SIGNAL(reagent_source, COMSIG_ITEM_ON_COMPOSTED, user)
		else
			transfer_amount = reagent_source.amount_per_transfer_from_this
			if(istype(reagent_source, /obj/item/reagent_containers/syringe/))
				var/obj/item/reagent_containers/syringe/syr = reagent_source
				visi_msg="[user] injects [target] with [syr]"
			// Beakers, bottles, buckets, etc.
			if(reagent_source.is_drainable())
				playsound(loc, 'sound/effects/slosh.ogg', 25, TRUE)

		if(visi_msg)
			visible_message(span_notice("[visi_msg]."))

		for(var/obj/machinery/ms13/agriculture/H in trays)
		//cause I don't want to feel like im juggling 15 tamagotchis and I can get to my real work of ripping flooring apart in hopes of validating my life choices of becoming a space-gardener
			//This was originally in apply_chemicals, but due to apply_chemicals only holding nutrients, we handle it here now.
			if(reagent_source.reagents.has_reagent(/datum/reagent/water, 1))
				var/water_amt = reagent_source.reagents.get_reagent_amount(/datum/reagent/water) * transfer_amount / reagent_source.reagents.total_volume
				H.adjust_waterlevel(round(water_amt))
				reagent_source.reagents.remove_reagent(/datum/reagent/water, water_amt)
			reagent_source.reagents.trans_to(H.reagents, transfer_amount, transfered_by = user)
			lastuser = WEAKREF(user)
			if(IS_EDIBLE(reagent_source) || istype(reagent_source, /obj/item/reagent_containers/pill))
				qdel(reagent_source)
				H.update_appearance()
				return 1
			H.update_appearance()
		if(reagent_source) // If the source wasn't composted and destroyed
			reagent_source.update_appearance()
		return 1

	else if(istype(O, /obj/item/seeds) && !istype(O, /obj/item/seeds/sample))
		if(!myseed)
			if(istype(O, /obj/item/seeds/kudzu))
				investigate_log("had Kudzu planted in it by [key_name(user)] at [AREACOORD(src)].", INVESTIGATE_BOTANY)
			if(!user.transferItemToLoc(O, src))
				return
			SEND_SIGNAL(O, COMSIG_SEED_ON_PLANTED, src)
			to_chat(user, span_notice("You plant [O]."))
			set_seed(O)
			TRAY_NAME_UPDATE
			age = 1
			set_plant_health(myseed.endurance)
			lastcycle = world.time
			return
		else
			to_chat(user, span_warning("[src] already has seeds in it!"))
			return

	else if(istype(O, /obj/item/shovel/ms13/rake))
		if(weedlevel > 0)
			user.visible_message(span_notice("[user] uproots the weeds."), span_notice("You remove the weeds from [src]."))
			set_weedlevel(0)
			return
		else
			to_chat(user, span_warning("This plot is completely devoid of weeds! It doesn't need uprooting."))
			return

	else if(istype(O, /obj/item/storage/bag/plants))
		attack_hand(user)
		for(var/obj/item/food/grown/G in locate(user.x,user.y,user.z))
			SEND_SIGNAL(O, COMSIG_TRY_STORAGE_INSERT, G, user, TRUE)
		return

	else if(default_unfasten_wrench(user, O))
		return

	else if(istype(O, /obj/item/shovel/ms13/spade))
		if(!myseed && !weedlevel)
			to_chat(user, span_warning("[src] doesn't have any plants or weeds!"))
			return
		user.visible_message(span_notice("[user] starts digging out [src]'s plants..."),
			span_notice("You start digging out [src]'s plants..."))
		if(O.use_tool(src, user, 50, volume=50) || (!myseed && !weedlevel))
			user.visible_message(span_notice("[user] digs out the plants in [src]!"), span_notice("You dig out all of [src]'s plants!"))
			if(myseed) //Could be that they're just using it as a de-weeder
				age = 0
				set_plant_health(0, update_icon = FALSE, forced = TRUE)
				lastproduce = 0
				set_seed(null)
				name = initial(name)
				desc = initial(desc)
			set_weedlevel(0) //Has a side effect of cleaning up those nasty weeds
			return
	else
		return ..()

/obj/machinery/ms13/agriculture/attackby_secondary(obj/item/weapon, mob/user, params)
	if (istype(weapon, /obj/item/reagent_containers/syringe))
		to_chat(user, span_warning("You can't get any extract out of this plant."))
		return SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN
	return SECONDARY_ATTACK_CALL_NORMAL

/obj/machinery/ms13/agriculture/can_be_unfasten_wrench(mob/user, silent)
	if (!unwrenchable)  // case also covered by NODECONSTRUCT checks in default_unfasten_wrench
		return CANT_UNFASTEN

	return ..()

/obj/machinery/ms13/agriculture/attack_hand(mob/user, list/modifiers)
	. = ..()
	if(.)
		return
	if(issilicon(user)) //How does AI know what plant is?
		return
	if(plant_status == HYDROTRAY_PLANT_HARVESTABLE)
		return myseed.harvest(user)

	else if(plant_status == HYDROTRAY_PLANT_DEAD)
		to_chat(user, span_notice("You remove the dead plant from [src]."))
		set_seed(null)
		update_appearance()
		TRAY_NAME_UPDATE
	else
		if(user)
			user.examinate(src)

/obj/machinery/ms13/agriculture/CtrlClick(mob/user)
	. = ..()
	if(!user.canUseTopic(src, BE_CLOSE, FALSE, NO_TK))
		return
	if(!powered())
		to_chat(user, span_warning("[name] has no power."))
		update_use_power(NO_POWER_USE)
		return
	if(!anchored)
		return
	set_self_sustaining(!self_sustaining)
	to_chat(user, span_notice("You [self_sustaining ? "activate" : "deactivated"] [src]'s autogrow function[self_sustaining ? ", maintaining the tray's health while using high amounts of power" : ""]."))

/obj/machinery/ms13/agriculture/AltClick(mob/user)
	return ..() // This hotkey is BLACKLISTED since it's used by /datum/component/simple_rotation

/**
 * Update Tray Proc
 * Handles plant harvesting on the tray side, by clearing the seed, names, description, and dead stat.
 * Shuts off autogrow if enabled.
 * Sends messages to the player about plants harvested, or if nothing was harvested at all.
 * * User - The mob who clears the tray.
 */
/obj/machinery/ms13/agriculture/proc/update_tray(mob/user, product_count)
	lastproduce = age
	if(istype(myseed, /obj/item/seeds/replicapod))
		to_chat(user, span_notice("You harvest from the [myseed.plantname]."))
	else if(product_count <= 0)
		to_chat(user, span_warning("You fail to harvest anything useful!"))
	else
		to_chat(user, span_notice("You harvest [product_count] items from the [myseed.plantname]."))
	if(!myseed.get_gene(/datum/plant_gene/trait/repeated_harvest))
		set_seed(null)
		name = initial(name)
		desc = initial(desc)
		TRAY_NAME_UPDATE
		if(self_sustaining) //No reason to pay for an empty tray.
			set_self_sustaining(FALSE)
	else
		set_plant_status(HYDROTRAY_PLANT_GROWING)
	update_appearance()
	SEND_SIGNAL(src, COMSIG_HYDROTRAY_ON_HARVEST, user, product_count)

///////////////////////////////////////////////////////////////////////////////
/obj/machinery/ms13/agriculture/soil
	name = "soil"
	desc = "A patch of dirt."
	icon = 'mojave/icons/hydroponics/dirt.dmi'
	icon_state = "dirt-0"
	base_icon_state = "dirt"
	smoothing_flags = SMOOTH_BITMASK
	smoothing_groups = list(SMOOTH_GROUP_SOIL)
	canSmoothWith = list(SMOOTH_GROUP_SOIL)
	density = FALSE
	use_power = NO_POWER_USE
	flags_1 = NODECONSTRUCT_1
	unwrenchable = FALSE
	maxnutri = 15
	var/border_icon = 'mojave/icons/hydroponics/dirt_border.dmi'

/obj/machinery/ms13/agriculture/soil/update_icon()
	. = ..()
	add_overlay(image(border_icon, icon_state, SOIL_EDGE_LAYER, pixel_x = -8, pixel_y = -8))

/obj/machinery/ms13/agriculture/soil/CtrlClick(mob/user)
	return //Soil has no electricity.

//// FARM MACHINERY ////
// MS13 Seed Extractor
/obj/structure/rustic_extractor
	name = "seed grinder"
	desc = "A crude grinding machine repurposed from kitchen appliances. Plants go in, seeds come out."
	icon = 'mojave/icons/hydroponics/equipment.dmi'
	icon_state = "seedextractor"
	density = TRUE
	anchored = TRUE

/obj/structure/rustic_extractor/proc/seedify(obj/item/O, t_max, obj/structure/rustic_extractor/extractor, mob/living/user)
	var/t_amount = 0
	var/list/seeds = list()
	if(t_max == -1)
		t_max = rand(1,2) //Slightly worse than the actual thing

	var/seedloc = O.loc
	if(extractor)
		seedloc = extractor.loc

	if(istype(O, /obj/item/food/grown/))
		var/obj/item/food/grown/F = O
		if(F.seed)
			if(user && !user.temporarilyRemoveItemFromInventory(O)) //couldn't drop the item
				return
			while(t_amount < t_max)
				var/obj/item/seeds/t_prod = F.seed.Copy()
				seeds.Add(t_prod)
				t_prod.forceMove(seedloc)
				t_amount++
			qdel(O)
			return seeds

	else if(istype(O, /obj/item/grown))
		var/obj/item/grown/F = O
		if(F.seed)
			if(user && !user.temporarilyRemoveItemFromInventory(O))
				return
			while(t_amount < t_max)
				var/obj/item/seeds/t_prod = F.seed.Copy()
				t_prod.forceMove(seedloc)
				t_amount++
			qdel(O)
		return 1

	return 0

/obj/structure/rustic_extractor/attackby(obj/item/O, mob/living/user, params)

	if(default_unfasten_wrench(user, O)) //So we can move them around
		return

	else if(seedify(O,-1, src, user))
		to_chat(user, "<span class='notice'>You extract some seeds.</span>")
		return
	else if(!user.combat_mode)
		to_chat(user, "<span class='warning'>You can't extract any seeds from \the [O.name]!</span>")
	else
		return ..()

//Fermentation Barrel
/obj/structure/fermenting_barrel/ms13
	icon = 'mojave/icons/hydroponics/equipment.dmi'
	icon_state = "barrel"

/obj/structure/fermenting_barrel/ms13/Initialize()
	. = ..()
	pixel_x = rand(-5, 5)
	pixel_y = rand(-5, 5)
