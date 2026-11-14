package im.mondchat.biz.controller.blocklist;

import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.dto.blocklist.BlocklistRequests;
import im.mondchat.biz.dto.blocklist.BlocklistResponses;
import im.mondchat.biz.service.blocklist.BlocklistService;
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

/** #21–#23 黑名单：列表任意来源可读，拉黑与取消拉黑只给真人（agent 在 service 里被拒）。 */
@RestController
@RequestMapping("/api/blocklist")
@RequiredArgsConstructor
public class BlocklistController {

    private final BlocklistService blocklistService;

    @GetMapping
    public BlocklistResponses.ListResponse list(CurrentAccount me,
            @RequestParam(name = "page", defaultValue = "1") int page,
            @RequestParam(name = "size", defaultValue = "50") int size) {
        return blocklistService.list(me, page, size);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public BlocklistResponses.Item block(CurrentAccount me,
            @Valid @RequestBody BlocklistRequests.CreateRequest request) {
        return blocklistService.block(me, request);
    }

    @DeleteMapping("/{accountId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void unblock(CurrentAccount me, @PathVariable("accountId") long accountId) {
        blocklistService.unblock(me, accountId);
    }
}
