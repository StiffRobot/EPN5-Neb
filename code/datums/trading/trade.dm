/datum/trader
	var/name = "unsuspicious trader"                            //The name of the trader in question
	var/origin = "some place"                                   //The place that they are trading from
	var/list/possible_origins                                   //Possible names of the trader origin
	var/disposition = 0                                         //The current disposition of them to us.
	var/trade_flags = TRADER_MONEY                              //Flags
	var/name_language                                                //If this is set to a language name this will generate a name from the language
	var/icon/portrait                                           //The icon that shows up in the menu @TODO

	var/list/wanted_items = list()                              //What items they enjoy trading for. Structure is (type = known/unknown)
	var/list/possible_wanted_items                              //List of all possible wanted items. Structure is (type = mode)
	var/list/possible_trading_items                             //List of all possible trading items. Structure is (type = mode)
	var/list/trading_items = list()                             //What items they are currently trading away.
	var/list/blacklisted_trade_items = list(/mob/living/carbon/human)
	                                                            //Things they will automatically refuse

	var/list/speech = list()                                    //The list of all their replies and messages. Structure is (id = talk)
	/*SPEECH IDS:
	hail_generic		When merchants hail a person
	hail_[race]			Race specific hails
	hail_deny			When merchant denies a hail

	insult_good			When the player insults a merchant while they are on good disposition
	insult_bad			When a player insults a merchatn when they are not on good disposition
	complement_accept	When the merchant accepts a complement
	complement_deny		When the merchant refuses a complement

	how_much			When a merchant tells the player how much something is.
	trade_complete		When a trade is made
	trade_refuse		When a trade is refused

	*/
	var/want_multiplier = 2                                     //How much wanted items are multiplied by when traded for
	var/insult_drop = 5                                         //How far disposition drops on insult
	var/compliment_increase = 5                                 //How far compliments increase disposition
	var/refuse_comms = 0                                        //Whether they refuse further communication

	var/mob_transfer_message = "You are transported to ORIGIN." //What message gets sent to mobs that get sold.

/datum/trader/New()
	..()
	if(name_language)
		if(name_language == TRADER_DEFAULT_NAME)
			name = capitalize(pick(first_names_female + first_names_male)) + " " + capitalize(pick(last_names))
		else
			var/datum/language/L = all_languages[name_language]
			if(L)
				name = L.get_random_name(pick(MALE,FEMALE))
	if(possible_origins && possible_origins.len)
		origin = pick(possible_origins)

	for(var/i in 3 to 6)
		add_to_pool(trading_items, possible_trading_items, force = 1)
		add_to_pool(wanted_items, possible_wanted_items, force = 1)

//If this hits 0 then they decide to up and leave.
/datum/trader/proc/tick()
	spawn(0)
		add_to_pool(trading_items, possible_trading_items, 200)
		add_to_pool(wanted_items, possible_wanted_items, 50)
		remove_from_pool(possible_trading_items, 9) //We want the stock to change every so often, so we make it so that they have roughly 10~11 ish items max
	return 1

/datum/trader/proc/remove_from_pool(var/list/pool, var/chance_per_item)
	if(pool && prob(chance_per_item * pool.len))
		var/i = rand(1,pool.len)
		pool[pool[i]] = null
		pool -= pool[i]

/datum/trader/proc/add_to_pool(var/list/pool, var/list/possible, var/base_chance = 100, var/force = 0)
	var/divisor = 1
	if(pool && pool.len)
		divisor = pool.len
	if(force || prob(base_chance/divisor))
		var/new_item = get_possible_item(possible)
		if(new_item)
			pool |= new_item

/datum/trader/proc/get_possible_item(var/list/trading_pool)
	if(!trading_pool || !trading_pool.len)
		return
	var/list/possible = list()
	for(var/type in trading_pool)
		var/status = trading_pool[type]
		if(status & TRADER_THIS_TYPE)
			possible += type
		if(status & TRADER_SUBTYPES_ONLY)
			possible += subtypesof(type)
		if(status & TRADER_BLACKLIST)
			possible -= type
		if(status & TRADER_BLACKLIST_SUB)
			possible -= subtypesof(type)

	if(possible.len)
		var/picked = pick(possible)
		var/atom/A = picked
		if(initial(A.name) in list("object", "item","weapon", "structure", "machinery", "Mecha", "organ", "snack")) //weed out a few of the common bad types. Reason we don't check types specifically is that (hopefully) further bad subtypes don't set their name up and are similar.
			return
		return picked

/datum/trader/proc/get_response(var/key, var/default)
	var/text
	if(speech && speech[key])
		text = speech[key]
	else
		text = default
	text = replacetext(text, "MERCHANT", name)
	return replacetext(text, "ORIGIN", origin)

/datum/trader/proc/print_trading_items(var/num)
	num = Clamp(num,1,trading_items.len)
	if(trading_items[num])
		var/atom/movable/M = trading_items[num]
		return "<b>[initial(M.name)]</b>"

/datum/trader/proc/get_item_value(var/trading_num)
	if(!trading_items[trading_items[trading_num]])
		var/type = trading_items[trading_num]
		var/value = get_value(type)
		value = round(rand(90,110)/100 * value) //For some reason rand doesn't like decimals.
		trading_items[type] = value
	return trading_items[trading_items[trading_num]]

/datum/trader/proc/offer_item_for_trade(var/atom/movable/offer, var/num)
	if(!offer)
		return 0
	num = Clamp(num,1, trading_items.len)
	var/is_wanted = 0
	if(is_type_in_list(offer,wanted_items))
		is_wanted = 1

	if(blacklisted_trade_items && blacklisted_trade_items.len && is_type_in_list(offer,blacklisted_trade_items))
		return 0

	if(istype(offer,/obj/item/weapon/spacecash))
		if(!(trade_flags & TRADER_MONEY))
			return 0
	else
		if(!(trade_flags & TRADER_GOODS) || ((trade_flags & TRADER_WANTED_ONLY) && !is_wanted))
			return 0

	var/trading_worth = get_item_value(num)
	var/offer_worth = get_value(offer)
	if(is_wanted)
		offer_worth *= 2
	if(!offer_worth)
		return 0
	var/percent = offer_worth/trading_worth
	if(percent > max(0.9,0.9-disposition/100))
		return trade(offer, num)
	return 0

/datum/trader/proc/hail(var/mob/user)
	var/specific
	if(istype(user, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = user
		if(H.species)
			specific = H.species.name
	else if(istype(user, /mob/living/silicon))
		specific = "silicon"
	if(!speech["hail_[specific]"])
		specific = "generic"
	. = get_response("hail_[specific]", "Greetings, MOB!")
	. = replacetext(., "MOB", user.name)

/datum/trader/proc/can_hail()
	if(!refuse_comms && prob(-disposition))
		refuse_comms = 1
	return !refuse_comms

/datum/trader/proc/insult()
	disposition -= rand(insult_drop, insult_drop * 2)
	if(prob(-disposition/10))
		refuse_comms = 1
	if(disposition > 50)
		return get_response("insult_good","What? I thought we were cool!")
	else
		return get_response("insult_bad", "Right back at you asshole!")

/datum/trader/proc/compliment()
	if(prob(-disposition))
		return get_response("compliment_deny", "Fuck you!")
	if(prob(100-disposition))
		disposition += rand(compliment_increase, compliment_increase * 2)
	return get_response("compliment_accept", "Thank you!")

/datum/trader/proc/trade(var/atom/movable/offer, var/num)
	var/type = trading_items[num]
	var/turf/T = get_turf(offer)
	if(istype(offer,/mob))
		var/text = mob_transfer_message
		offer << replacetext(text, "ORIGIN", origin)
	if(istype(offer, /obj/mecha))
		var/obj/mecha/M = offer
		M.wreckage = null //So they don't ruin the illusion
	qdel(offer)
	var/atom/movable/M = new type(T)
	playsound(T, 'sound/effects/teleport.ogg', 50, 1)

	disposition += rand(compliment_increase,compliment_increase*3) //Traders like it when you trade with them

	return M

/datum/trader/proc/how_much_do_you_want(var/num)
	var/atom/movable/M = trading_items[num]
	. = get_response("how_much", "Hmm.... how about VALUE thalers?")
	. = replacetext(.,"VALUE",get_item_value(num))
	. = replacetext(.,"ITEM", initial(M.name))