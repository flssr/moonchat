package im.mondchat.biz.controller.room;

import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.dto.room.RoomRequests;
import im.mondchat.biz.dto.room.RoomResponses;
import im.mondchat.biz.service.room.RoomService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** #12–#18 群七条：建群、我的群、群信息、成员列表、拉人、退群、移除成员。 */
@RestController
@RequestMapping("/api/rooms")
@RequiredArgsConstructor
public class RoomController {

    private final RoomService roomService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public RoomResponses.CreateResponse create(CurrentAccount me,
            @Valid @RequestBody RoomRequests.CreateRequest request) {
        return roomService.create(me, request);
    }

    @GetMapping
    public RoomResponses.ListResponse mine(CurrentAccount me) {
        return roomService.mine(me);
    }

    @GetMapping("/{roomId}")
    public RoomResponses.InfoResponse info(CurrentAccount me, @PathVariable("roomId") long roomId) {
        return roomService.info(me, roomId);
    }

    @GetMapping("/{roomId}/members")
    public RoomResponses.MembersResponse members(CurrentAccount me, @PathVariable("roomId") long roomId,
            @RequestParam(name = "page", defaultValue = "1") int page,
            @RequestParam(name = "size", defaultValue = "50") int size) {
        return roomService.members(me, roomId, page, size);
    }

    @PostMapping("/{roomId}/members")
    @ResponseStatus(HttpStatus.CREATED)
    public RoomResponses.MemberResponse addMember(CurrentAccount me, @PathVariable("roomId") long roomId,
            @Valid @RequestBody RoomRequests.AddMemberRequest request) {
        return roomService.addMember(me, roomId, request);
    }

    /** 「我自己」不是账号 id，写成路径尾段比 `?me=true` 直白（§1.1 的第二处例外）。 */
    @DeleteMapping("/{roomId}/members/me")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void leave(CurrentAccount me, @PathVariable("roomId") long roomId) {
        roomService.leave(me, roomId);
    }

    @DeleteMapping("/{roomId}/members/{accountId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void removeMember(CurrentAccount me, @PathVariable("roomId") long roomId,
            @PathVariable("accountId") long accountId) {
        roomService.removeMember(me, roomId, accountId);
    }
}
