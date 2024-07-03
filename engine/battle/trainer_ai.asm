; Prepare the state representation
PrepareState:
    ; Load current HP of the enemy Pokémon
    ld a, [wEnemyMonHP + 1]
    ld [stateEnemyHP], a

    ; Load type effectiveness, move type, and move power
    ld a, [wTypeEffectiveness]
    ld [stateTypeEffectiveness], a
    ld a, [wEnemyMoveType]
    ld [stateMoveType], a
    ld a, [wEnemyMovePower]
    ld [stateMovePower], a

    ; Load available moves and their properties
    ld hl, wEnemyMonMoves
    ld de, stateMoves
    ld bc, NUM_MOVES * MOVE_LENGTH
    call CopyData

    ; Load status conditions
    ld a, [wBattleMonStatus]
    ld [stateStatus], a

    ret

; Call PPO model to get move probabilities
CallPPOModel:
    call PrepareState
    ; Call the external PPO model function
    call PPOModelFunction

    ; Assume the model writes probabilities to a fixed location
    ld hl, stateMoveProbabilities
    ; Now hl points to the move probabilities
    ret

; Calculate cumulative probabilities
CalculateCumulativeProbabilities:
    ld hl, stateMoveProbabilities
    ld a, [hl]
    ld [cumulativeProb1], a
    inc hl
    ld a, [hl]
    ld a, [cumulativeProb1]
    add a, b
    ld [cumulativeProb2], a
    inc hl
    ld a, [hl]
    ld a, [cumulativeProb2]
    add a, b
    ld [cumulativeProb3], a
    inc hl
    ld a, [hl]
    ld a, [cumulativeProb3]
    add a, b
    ld [cumulativeProb4], a

    ret

; Select a move based on the probabilities
SelectMoveBasedOnProbabilities:
    ; Generate a random number
    call Random
    ld [randomNumber], a

    call CalculateCumulativeProbabilities

    ; Compare random number with cumulative probabilities to select a move
    ld a, [randomNumber]
    ld b, a
    ld a, [cumulativeProb1]
    cp a
    jr c, .selectMove1
    ld a, [cumulativeProb2]
    cp a
    jr c, .selectMove2
    ld a, [cumulativeProb3]
    cp a
    jr c, .selectMove3
    ; If not less than cumulativeProb3, select move 4

.selectMove4:
    ld hl, wEnemyMonMoves
    ld de, MOVE_LENGTH * 3
    add hl, de
    ld a, [hl]
    ld [selectedMove], a
    ret

.selectMove1:
    ld hl, wEnemyMonMoves
    ld a, [hl]
    ld [selectedMove], a
    ret

.selectMove2:
    ld hl, wEnemyMonMoves
    ld de, MOVE_LENGTH
    add hl, de
    ld a, [hl]
    ld [selectedMove], a
    ret

.selectMove3:
    ld hl, wEnemyMonMoves
    ld de, MOVE_LENGTH * 2
    add hl, de
    ld a, [hl]
    ld [selectedMove], a
    ret

; Define storage for cumulative probabilities and selected move
cumulativeProb1:   db 0
cumulativeProb2:   db 0
cumulativeProb3:   db 0
cumulativeProb4:   db 0
selectedMove:      db 0
randomNumber:      db 0

; This is a placeholder function that represents the PPO model
; In a real implementation, this would call the PPO model and write the probabilities to moveProbabilities
PPOModelFunction:
    ; Placeholder: Just return uniform probabilities
    ld hl, stateMoveProbabilities
    ld a, 25
    ld [hl], a
    inc hl
    ld [hl], a
    inc hl
    ld [hl], a
    inc hl
    ld [hl], a
    ret

; Define storage for rewards and learning rate
reward:       db 0
learningRate: db 1  ; Example learning rate (0.01 scaled to 1 for simplicity)

; Calculate reward based on the outcome of the battle
CalculateReward:
    ; Check if the enemy Pokémon is defeated
    ld a, [wEnemyMonHP + 1]
    cp 0
    jr z, .enemyDefeated

    ; Neutral action reward
    ld a, 0
    ld [reward], a
    ret

.enemyDefeated:
    ld a, 100  ; Reward value for defeating enemy
    ld [reward], a
    ret

; Update the move probabilities based on the reward
UpdatePolicy:
    ld hl, stateMoveProbabilities
    ld a, [selectedMove]
    ld b, a

    ; Move hl to the correct position in the probabilities array
    ld c, b
.loop_hl:
    dec c
    jr z, .adjust_probability
    inc hl
    jr .loop_hl

.adjust_probability:
    ; Adjust the probability for the selected move
    ld a, [reward]
    ld c, a
    ld a, [learningRate]
    call Multiply ; result in de
    ld a, d
    add a, [hl]
    ld [hl], a

    ; Normalize probabilities
    call NormalizeProbabilities

    ret

; Multiply values in a and c, store result in de
Multiply:
    xor d
    xor e
    ld b, 8
.mul_loop:
    sla c
    rl e
    rl d
    jr nc, .skip_add
    add a, d
.skip_add:
    dec b
    jr nz, .mul_loop
    ret

; Normalize probabilities to ensure they sum to 100
NormalizeProbabilities:
    ld hl, stateMoveProbabilities ; Point HL to the start of the probabilities array
    xor a                         ; Clear the accumulator (A) to use it for summing
    ld b, 0                       ; Clear register B which will hold the sum
    ld c, NUM_MOVES               ; Load the number of moves into C

.loop_sum:
    add a, [hl]                   ; Add the value at HL to A
    ld b, a                       ; Store the sum in B
    inc hl                        ; Increment HL to point to the next value
    dec c                         ; Decrement C (loop counter)
    jr nz, .loop_sum              ; Repeat until C is zero

    ; Normalize each probability
    ld hl, stateMoveProbabilities ; Point HL back to the start of the probabilities array
    ld e, b                       ; Load the sum of all probabilities into E
    ld c, NUM_MOVES               ; Reload the number of moves into C

.loop_normalize:
    ld a, [hl]                    ; Load the current probability into A
    call DivideByE                ; Divide A by E (sum of probabilities) and store result back in A
    ld [hl], a                    ; Store the normalized value back into the array
    inc hl                        ; Move to the next probability
    dec c                         ; Decrement C (loop counter)
    jr nz, .loop_normalize        ; Repeat until C is zero

    ret                           ; Return from the subroutine

; Divide value in A by value in E, store result in A
DivideByE:
    ld b, 0                      ; Clear register B which will count the quotient
.div_loop:
    sub e                        ; Subtract E from A
    jr c, .done                  ; If the result is negative, we are done
    inc b                        ; Otherwise, increment B (quotient)
    jr .div_loop                 ; Repeat the loop

.done:
    add a, e                     ; Correct A by adding back E (because the last subtraction was not valid)
    ld a, b                      ; Load the quotient back into A
    ret                          ; Return from the subroutine

; Define storage for state representation and move probabilities
stateEnemyHP:               ds 1
stateTypeEffectiveness:     ds 1
stateMoveType:              ds 1
stateMovePower:             ds 1
stateMoves:                 ds NUM_MOVES * MOVE_LENGTH
stateStatus:                ds 1
stateMoveProbabilities:     ds NUM_MOVES

AIEnemyTrainerChooseMoves:
    call CallPPOModel
    ; Assume that the probabilities from the PPO model are stored in stateMoveProbabilities
    ld hl, wBuffer ; init temporary move selection array

    ; Use the probabilities to select moves
    call SelectMoveBasedOnProbabilities
    ld a, [selectedMove]
    ld [hli], a   ; move 1
    call SelectMoveBasedOnProbabilities
    ld a, [selectedMove]
    ld [hli], a   ; move 2
    call SelectMoveBasedOnProbabilities
    ld a, [selectedMove]
    ld [hli], a   ; move 3
    call SelectMoveBasedOnProbabilities
    ld a, [selectedMove]
    ld [hl], a    ; move 4

    ret

INCLUDE "data/trainers/move_choices.asm"
INCLUDE "data/trainers/pic_pointers_money.asm"
INCLUDE "data/trainers/names.asm"
INCLUDE "engine/battle/misc.asm"
INCLUDE "engine/battle/read_trainer_party.asm"
INCLUDE "data/trainers/special_moves.asm"
INCLUDE "data/trainers/parties.asm"

TrainerAI:
    and a
    ld a, [wIsInBattle]
    dec a
    ret z ; if not a trainer, we're done here
    ld a, [wLinkState]
    cp LINK_STATE_BATTLING
    ret z ; if in a link battle, we're done as well
    ld a, [wTrainerClass]
    dec a
    ld c, a
    ld b, 0
    ld hl, TrainerAIPointers
    add hl, bc
    add hl, bc
    add hl, bc
    ld a, [wAICount]
    and a
    ret z ; if no AI uses left, we're done here
    inc hl
    inc a
    jr nz, .getpointer
    dec hl
    ld a, [hli]
    ld [wAICount], a
.getpointer
    ld a, [hli]
    ld h, [hl]
    ld l, a
    call Random
    call AIEnemyTrainerChooseMoves

    ; Calculate reward and update policy after the move is executed
    call CalculateReward
    call UpdatePolicy

    ret

INCLUDE "data/trainers/ai_pointers.asm"

JugglerAI:
	cp 25 percent + 1
	ret nc
	jp AISwitchIfEnoughMons

BlackbeltAI:
	cp 13 percent - 1
	ret nc
	jp AIUseXAttack

GiovanniAI:
	cp 25 percent + 1
	ret nc
	jp AIUseGuardSpec

CooltrainerMAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXAttack

CooltrainerFAI:
	; The intended 25% chance to consider switching will not apply.
	; Uncomment the line below to fix this.
	cp 25 percent + 1
	; ret nc
	ld a, 10
	call AICheckIfHPBelowFraction
	jp c, AIUseHyperPotion
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AISwitchIfEnoughMons

BrockAI:
; if his active monster has a status condition, use a full heal
	ld a, [wEnemyMonStatus]
	and a
	ret z
	jp AIUseFullHeal

MistyAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXDefend

LtSurgeAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXSpeed

ErikaAI:
	cp 50 percent + 1
	ret nc
	ld a, 10
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseSuperPotion

KogaAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXAttack

BlaineAI:
	cp 25 percent + 1
	ret nc
	jp AIUseSuperPotion

SabrinaAI:
	cp 25 percent + 1
	ret nc
	ld a, 10
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseHyperPotion

Rival2AI:
	cp 13 percent - 1
	ret nc
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUsePotion

Rival3AI:
	cp 13 percent - 1
	ret nc
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseFullRestore

LoreleiAI:
	cp 50 percent + 1
	ret nc
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseSuperPotion

BrunoAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXDefend

AgathaAI:
	cp 8 percent
	jp c, AISwitchIfEnoughMons
	cp 50 percent + 1
	ret nc
	ld a, 4
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseSuperPotion

LanceAI:
	cp 50 percent + 1
	ret nc
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseHyperPotion

GenericAI:
	and a ; clear carry
	ret

; end of individual trainer AI routines

DecrementAICount:
	ld hl, wAICount
	dec [hl]
	scf
	ret

AIPlayRestoringSFX:
	ld a, SFX_HEAL_AILMENT
	jp PlaySoundWaitForCurrent

AIUseFullRestore:
	call AICureStatus
	ld a, FULL_RESTORE
	ld [wAIItem], a
	ld de, wHPBarOldHP
	ld hl, wEnemyMonHP + 1
	ld a, [hld]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
	inc de
	ld hl, wEnemyMonMaxHP + 1
	ld a, [hld]
	ld [de], a
	inc de
	ld [wHPBarMaxHP], a
	ld [wEnemyMonHP + 1], a
	ld a, [hl]
	ld [de], a
	ld [wHPBarMaxHP+1], a
	ld [wEnemyMonHP], a
	jr AIPrintItemUseAndUpdateHPBar

AIUsePotion:
; enemy trainer heals his monster with a potion
	ld a, POTION
	ld b, 20
	jr AIRecoverHP

AIUseSuperPotion:
; enemy trainer heals his monster with a super potion
	ld a, SUPER_POTION
	ld b, 50
	jr AIRecoverHP

AIUseHyperPotion:
; enemy trainer heals his monster with a hyper potion
	ld a, HYPER_POTION
	ld b, 200
	; fallthrough

AIRecoverHP:
; heal b HP and print "trainer used $(a) on pokemon!"
	ld [wAIItem], a
	ld hl, wEnemyMonHP + 1
	ld a, [hl]
	ld [wHPBarOldHP], a
	add b
	ld [hld], a
	ld [wHPBarNewHP], a
	ld a, [hl]
	ld [wHPBarOldHP+1], a
	ld [wHPBarNewHP+1], a
	jr nc, .next
	inc a
	ld [hl], a
	ld [wHPBarNewHP+1], a
.next
	inc hl
	ld a, [hld]
	ld b, a
	ld de, wEnemyMonMaxHP + 1
	ld a, [de]
	dec de
	ld [wHPBarMaxHP], a
	sub b
	ld a, [hli]
	ld b, a
	ld a, [de]
	ld [wHPBarMaxHP+1], a
	sbc b
	jr nc, AIPrintItemUseAndUpdateHPBar
	inc de
	ld a, [de]
	dec de
	ld [hld], a
	ld [wHPBarNewHP], a
	ld a, [de]
	ld [hl], a
	ld [wHPBarNewHP+1], a
	; fallthrough

AIPrintItemUseAndUpdateHPBar:
	call AIPrintItemUse_
	hlcoord 2, 2
	xor a
	ld [wHPBarType], a
	predef UpdateHPBar2
	jp DecrementAICount

AISwitchIfEnoughMons:
; enemy trainer switches if there are 2 or more unfainted mons in party
	ld a, [wEnemyPartyCount]
	ld c, a
	ld hl, wEnemyMon1HP

	ld d, 0 ; keep count of unfainted monsters

	; count how many monsters haven't fainted yet
.loop
	ld a, [hli]
	ld b, a
	ld a, [hld]
	or b
	jr z, .Fainted ; has monster fainted?
	inc d
.Fainted
	push bc
	ld bc, wEnemyMon2 - wEnemyMon1
	add hl, bc
	pop bc
	dec c
	jr nz, .loop

	ld a, d ; how many available monsters are there?
	cp 2    ; don't bother if only 1
	jp nc, SwitchEnemyMon
	and a
	ret

SwitchEnemyMon:

; prepare to withdraw the active monster: copy hp, number, and status to roster

	ld a, [wEnemyMonPartyPos]
	ld hl, wEnemyMon1HP
	ld bc, wEnemyMon2 - wEnemyMon1
	call AddNTimes
	ld d, h
	ld e, l
	ld hl, wEnemyMonHP
	ld bc, 4
	call CopyData

	ld hl, AIBattleWithdrawText
	call PrintText

	; This wFirstMonsNotOutYet variable is abused to prevent the player from
	; switching in a new mon in response to this switch.
	ld a, 1
	ld [wFirstMonsNotOutYet], a
	callfar EnemySendOut
	xor a
	ld [wFirstMonsNotOutYet], a

	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	scf
	ret

AIBattleWithdrawText:
	text_far _AIBattleWithdrawText
	text_end

AIUseFullHeal:
	call AIPlayRestoringSFX
	call AICureStatus
	ld a, FULL_HEAL
	jp AIPrintItemUse

AICureStatus:
; cures the status of enemy's active pokemon
	ld a, [wEnemyMonPartyPos]
	ld hl, wEnemyMon1Status
	ld bc, wEnemyMon2 - wEnemyMon1
	call AddNTimes
	xor a
	ld [hl], a ; clear status in enemy team roster
	ld [wEnemyMonStatus], a ; clear status of active enemy
	ld hl, wEnemyBattleStatus3
	res 0, [hl]
	ret

AIUseXAccuracy: ; unused
	call AIPlayRestoringSFX
	ld hl, wEnemyBattleStatus2
	set 0, [hl]
	ld a, X_ACCURACY
	jp AIPrintItemUse

AIUseGuardSpec:
	call AIPlayRestoringSFX
	ld hl, wEnemyBattleStatus2
	set 1, [hl]
	ld a, GUARD_SPEC
	jp AIPrintItemUse

AIUseDireHit: ; unused
	call AIPlayRestoringSFX
	ld hl, wEnemyBattleStatus2
	set 2, [hl]
	ld a, DIRE_HIT
	jp AIPrintItemUse

AICheckIfHPBelowFraction:
; return carry if enemy trainer's current HP is below 1 / a of the maximum
	ldh [hDivisor], a
	ld hl, wEnemyMonMaxHP
	ld a, [hli]
	ldh [hDividend], a
	ld a, [hl]
	ldh [hDividend + 1], a
	ld b, 2
	call Divide
	ldh a, [hQuotient + 3]
	ld c, a
	ldh a, [hQuotient + 2]
	ld b, a
	ld hl, wEnemyMonHP + 1
	ld a, [hld]
	ld e, a
	ld a, [hl]
	ld d, a
	ld a, d
	sub b
	ret nz
	ld a, e
	sub c
	ret

AIUseXAttack:
	ld b, $A
	ld a, X_ATTACK
	jr AIIncreaseStat

AIUseXDefend:
	ld b, $B
	ld a, X_DEFEND
	jr AIIncreaseStat

AIUseXSpeed:
	ld b, $C
	ld a, X_SPEED
	jr AIIncreaseStat

AIUseXSpecial:
	ld b, $D
	ld a, X_SPECIAL
	; fallthrough

AIIncreaseStat:
	ld [wAIItem], a
	push bc
	call AIPrintItemUse_
	pop bc
	ld hl, wEnemyMoveEffect
	ld a, [hld]
	push af
	ld a, [hl]
	push af
	push hl
	ld a, XSTATITEM_DUPLICATE_ANIM
	ld [hli], a
	ld [hl], b
	callfar StatModifierUpEffect
	pop hl
	pop af
	ld [hli], a
	pop af
	ld [hl], a
	jp DecrementAICount

AIPrintItemUse:
	ld [wAIItem], a
	call AIPrintItemUse_
	jp DecrementAICount

AIPrintItemUse_:
; print "x used [wAIItem] on z!"
	ld a, [wAIItem]
	ld [wd11e], a
	call GetItemName
	ld hl, AIBattleUseItemText
	jp PrintText

AIBattleUseItemText:
	text_far _AIBattleUseItemText
	text_end
