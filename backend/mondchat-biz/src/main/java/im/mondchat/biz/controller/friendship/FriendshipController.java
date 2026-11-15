package im.mondchat.biz.controller.friendship;

import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.dto.friendship.FriendshipRequests;
import im.mondchat.biz.dto.friendship.FriendshipResponses;
import im.mondchat.biz.service.friendship.FriendshipService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** #8–#11 好友四条：真人客户端与 agent 端点走同一套，差别只在凭据与限流。 */
@RestController
@RequestMapping("/api/friendships")
@RequiredArgsConstructor
public class FriendshipController {

    private final FriendshipService friendshipService;

    @GetMapping
    public FriendshipResponses.ListResponse list(CurrentAccount me,
            @RequestParam(name = "status", required = false) String status) {
        return friendshipService.list(me, status);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public FriendshipResponses.RequestResponse request(CurrentAccount me,
            @Valid @RequestBody FriendshipRequests.CreateRequest request) {
        return friendshipService.request(me, request);
    }

    /** `accept` 有 body（关系变了），`reject` 没有（只写了 tombstone）。 */
    @PostMapping("/{peerAccountId}")
    public ResponseEntity<FriendshipResponses.AcceptResponse> respond(CurrentAccount me,
            @PathVariable("peerAccountId") long peerAccountId,
            @Valid @RequestBody FriendshipRequests.RespondRequest request) {
        if ("accept".equals(request.action())) {
            return ResponseEntity.ok(friendshipService.accept(me, peerAccountId));
        }
        friendshipService.reject(me, peerAccountId);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/{peerAccountId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(CurrentAccount me, @PathVariable("peerAccountId") long peerAccountId) {
        friendshipService.delete(me, peerAccountId);
    }
}
