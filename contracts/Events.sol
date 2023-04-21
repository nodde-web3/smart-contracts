// SPDX-License-Identifier: MIT                                                

pragma solidity ^0.8.18;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IMainNFT {
    function ownerOf(uint256) external view returns (address);
    function onlyAuthor(address, uint256) external pure returns (bool);
    function isAddressExist(address, address[] memory) external pure returns (bool);
    function contractFeeForAuthor(uint256, uint256) external view returns(uint256);
    function commissionCollector() external view returns (address);
    function addAuthorsRating(address, uint256, uint256) external;
    function setVerfiedContracts(bool, address) external;
}

contract Events is ReentrancyGuard {
    using SafeMath for uint256;

    address verifierProvider;
    IMainNFT mainNFT;

    enum Types {
        notModerated,
        moderated
    }

    struct Participants {
        address[] confirmed;
        address[] notConfirmed;
        address[] rejected;
    }

    struct Rating {
        uint256 like;
        uint256 dislike;
        uint256 cancelled;
    }

    struct PaymentSession {
        bool fundsWithdrawn;
        address tokenAddress;
        uint256 price;
        uint256 expirationTime;
        uint256 eventStartTime;
        uint256 periodOfPenalty;
        uint256 maxParticipants;
        string name;
        Types typeOf;
        Participants participants;
        Rating rating;
    }

    mapping(uint256 => mapping(address => bool)) public whiteListByAuthor;
    mapping(uint256 => mapping(address => bool)) public blackListByAuthor;
    mapping(uint256 => PaymentSession[]) public paymentSessionByAuthor;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public participantVoted;
    mapping(uint256 => mapping(uint256 => mapping(address => string))) public invitationToTg;
    mapping(address => uint256) internal blockedForWithdraw;

    event Received(address indexed sender, uint256 value);
    event NewPaymentSessionCreated(uint256 indexed author, string name, address token, uint256 price, uint256 expirationTime, uint256 maxParticipants, Types typeOf);
    event AwaitingConfirmation(address indexed participant, uint256 indexed author, uint256 indexed paymentSessionId);
    event PurchaseConfirmed(address indexed participant, uint256 indexed author, uint256 indexed paymentSessionId);
    event PurchaseRejected(address indexed participant, uint256 indexed author, uint256 indexed paymentSessionId);
    event PurchaseCanceled(address indexed participant, uint256 indexed author, uint256 indexed paymentSessionId);
    event NewVote(bool isLike, address indexed participant, uint256 indexed author, uint256 indexed paymentSessionId);
    
    modifier onlyOwner() {
        require(owner() == msg.sender, "Only owner");
        _;
    }

    modifier onlyAuthor(uint256 author) {
        require(mainNFT.onlyAuthor(msg.sender, author), "Only for Author");
        _;
    }

    modifier onlyVerifierProvider(){
        require(verifierProvider == msg.sender, "Only verifier provider");
        _;
    }

    modifier supportsERC20(address _address){
        require(
            _address == address(0) || IERC20(_address).totalSupply() > 0 && IERC20(_address).allowance(_address, _address) >= 0,
            "Is not ERC20"
            );
        _;
    }
    
    modifier paymentSessionIsOpenForSender(uint256 author, uint256 paymentSessionId){
        require(!blackListByAuthor[author][msg.sender], "You blacklisted");
        PaymentSession memory paymentSession = paymentSessionByAuthor[author][paymentSessionId];
        require(
            paymentSession.expirationTime > block.timestamp && paymentSession.participants.confirmed.length < paymentSession.maxParticipants, 
            "Payment session is closed"
            );
        Participants memory participants = paymentSession.participants;
        require(!mainNFT.isAddressExist(msg.sender, participants.rejected), "You denied");
        require(!mainNFT.isAddressExist(msg.sender, participants.notConfirmed), "Expect decision on your candidacy");
        require(!mainNFT.isAddressExist(msg.sender, participants.confirmed), "You already on list");
        _;
    }

    constructor(address _mainNFTAddress, address _verifierProvider) {
        mainNFT = IMainNFT(_mainNFTAddress);
        mainNFT.setVerfiedContracts(true, address(this));
        setVerifierProvider(_verifierProvider);
    }

    /***************Author options BGN***************/
    function createNewPaymentSessionByEth(
        uint256 author, 
        uint256 price, 
        uint256 expirationTime, 
        uint256 eventStartTime,
        uint256 periodOfPenalty,
        uint256 maxParticipants, 
        Types typeOf, 
        string memory name) public onlyAuthor(author){
            require(price >= 10**6, "Low price");
            createNewPaymentSessionByToken(author, address(0), price, expirationTime, eventStartTime, periodOfPenalty, maxParticipants, typeOf, name);
        }

    function createNewPaymentSessionByToken(
        uint256 author, 
        address tokenAddress, 
        uint256 price, 
        uint256 expirationTime, 
        uint256 eventStartTime,
        uint256 periodOfPenalty,
        uint256 maxParticipants, 
        Types typeOf, 
        string memory name) supportsERC20(tokenAddress) public onlyAuthor(author){
            require(price > 0, "Low price");
            require(
                expirationTime > block.timestamp && eventStartTime >= expirationTime && eventStartTime.add(periodOfPenalty) >= eventStartTime,
                "Timestamp error");
            Rating memory rating = Rating(0, 0, 0);  
            Participants memory participants = Participants(
                new address[](0),
                new address[](0),
                new address[](0)
            );        
            PaymentSession memory paymentSession = PaymentSession ({
                fundsWithdrawn: false,
                tokenAddress: tokenAddress,
                price: price,
                expirationTime: expirationTime,
                eventStartTime: eventStartTime,
                periodOfPenalty: periodOfPenalty,
                maxParticipants: maxParticipants,
                name: name,
                typeOf: typeOf,
                participants: participants,
                rating: rating
            });
            paymentSessionByAuthor[author].push(paymentSession);
            emit NewPaymentSessionCreated(author, name, tokenAddress, price, expirationTime, maxParticipants, typeOf);
    }

    function addToWhiteList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = false;
        whiteListByAuthor[author][user] = true;
    }

    function removeWhiteList(address user, uint256 author) public onlyAuthor(author){
        whiteListByAuthor[author][user] = false;
    }

    function addToBlackList(address user, uint256 author) public onlyAuthor(author){
        whiteListByAuthor[author][user] = false;
        blackListByAuthor[author][user] = true;
    }

    function removeBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = false;
    }

    function confirmParticipants(address participant, uint256 author, uint256 paymentSessionId) public onlyAuthor(author) returns(bool success) {
        PaymentSession storage paymentSession = paymentSessionByAuthor[author][paymentSessionId];
        Participants storage participants = paymentSession.participants;
        require(mainNFT.isAddressExist(participant, participants.notConfirmed), "Is denied");
        address[] storage notConfirmed = participants.notConfirmed;
        success = _removeAddressFromArray(participant, notConfirmed);
        if (success) {
            participants.confirmed.push(participant);
            _unblockAndPay(paymentSession.tokenAddress, paymentSession.price, author);
            emit PurchaseConfirmed(participant, author, paymentSessionId);
        }
    }

    function unconfirmParticipants(address participant, uint256 author, uint256 paymentSessionId) public onlyAuthor(author) returns(bool success) {
        PaymentSession storage paymentSession = paymentSessionByAuthor[author][paymentSessionId];
        require(paymentSession.expirationTime > block.timestamp, "The time for unconfirm participant has expired");
        Participants storage participants = paymentSession.participants;
        require(mainNFT.isAddressExist(participant, participants.notConfirmed), "Is denied");
        address[] storage notConfirmed = participants.notConfirmed;
        success = _removeAddressFromArray(participant, notConfirmed);
        if (success){
            participants.rejected.push(participant);
            _unblockAndReject(participant, paymentSession.tokenAddress, paymentSession.price);
            emit PurchaseRejected(participant, author, paymentSessionId);
        }
    }

    function withdrawAfterPaymentSession(uint256 author, uint256 paymentSessionId) public onlyAuthor(author){
        PaymentSession storage paymentSession = paymentSessionByAuthor[author][paymentSessionId];
        require(!paymentSession.fundsWithdrawn, "Funds have already been withdrawn");
        Participants memory participants = paymentSession.participants;
        require(participants.confirmed.length > 0, "Funds are not enough");
        require(
            paymentSession.eventStartTime.add(paymentSession.periodOfPenalty) >= block.timestamp, 
            "The time for blocking funds has not expired"
        );
        paymentSession.fundsWithdrawn = true;
        uint256 amount = participants.confirmed.length.mul(paymentSession.price);
        _unblockAndPay(paymentSession.tokenAddress, amount, author);
    }

    function _unblockAndPay(address tokenAddress, uint256 tokenAmount, uint256 author) internal {
        if (tokenAddress == address(0)){
            _paymentEth(author, tokenAmount);
        } else {
            _paymentToken(address(this), tokenAddress, tokenAmount, author);
        }
        blockedForWithdraw[tokenAddress] -= tokenAmount;
    }

    function _unblockAndReject(address participant, address tokenAddress, uint256 tokenAmount) internal nonReentrant {
        if (tokenAddress == address(0)){
            (bool success, ) = participant.call{value: tokenAmount}("");
            require(success, "fail");
        } else {
            IERC20 token = IERC20(tokenAddress);
            uint256 contractBalance = token.balanceOf(address(this));
            if (contractBalance < tokenAmount){
                tokenAmount = contractBalance;
            }
            token.transfer(participant, tokenAmount);
        }
        blockedForWithdraw[tokenAddress] -= tokenAmount;
    }

    function _paymentEth(uint256 author, uint256 value) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, value);
        uint256 amount = value - contractFee;
        (bool success1, ) = owner().call{value: contractFee}("");
        (bool success2, ) = ownerOf(author).call{value: amount}("");
        require(success1 && success2, "fail");
        mainNFT.addAuthorsRating(address(0), value, author);
    }

    function _paymentToken(address sender, address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        IERC20 token = IERC20(tokenAddress);
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        token.transferFrom(sender, owner(), contractFee);
        uint256 amount = tokenAmount - contractFee;
        token.transferFrom(sender, ownerOf(author), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }

    function getAllPaymentSessionsByAuthor(uint256 author) public view returns (PaymentSession[] memory){
        return paymentSessionByAuthor[author];
    }

    /***************Author options END***************/

    /***************User interfaces BGN***************/
    function _blockTokens(address tokenAddress, uint256 tokenAmount) internal nonReentrant {
        if (tokenAddress != address(0)){
            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), tokenAmount);
        }
        blockedForWithdraw[tokenAddress] += tokenAmount;
    }

    function buyTicketForPaymentSession(uint256 author, uint256 paymentSessionId) public paymentSessionIsOpenForSender(author, paymentSessionId) payable{
        PaymentSession storage paymentSession = paymentSessionByAuthor[author][paymentSessionId];
        Participants storage participants = paymentSession.participants;
        address tokenAddress = paymentSession.tokenAddress;
        uint256 price = paymentSession.price;
        require(tokenAddress == address(0) && price == msg.value || tokenAddress != address(0), "Error value");
        _blockTokens(tokenAddress, price);

        if (whiteListByAuthor[author][msg.sender] || paymentSession.typeOf == Types.notModerated){
            participants.confirmed.push(msg.sender);
            emit PurchaseConfirmed(msg.sender, author, paymentSessionId);
        } else {
            participants.notConfirmed.push(msg.sender);
            emit AwaitingConfirmation(msg.sender, author, paymentSessionId);
        }
    }

    function cancelByParticipant(uint256 author, uint256 paymentSessionId) public returns(bool success) {
        PaymentSession storage paymentSession = paymentSessionByAuthor[author][paymentSessionId];
        Participants storage participants = paymentSession.participants;
        require(
            paymentSession.eventStartTime.add(paymentSession.periodOfPenalty) < block.timestamp, 
            "The time for cancellation has expired. Contact the author of the event"
        );
        require(
            mainNFT.isAddressExist(msg.sender, participants.notConfirmed) || mainNFT.isAddressExist(msg.sender, participants.confirmed), 
            "You are not in lists"
        );
        
        if (mainNFT.isAddressExist(msg.sender, participants.notConfirmed)){
            address[] storage notConfirmed = participants.notConfirmed;
            success = _removeAddressFromArray(msg.sender, notConfirmed);
            _unblockAndReject(msg.sender, paymentSession.tokenAddress, paymentSession.price);
        }
        if (mainNFT.isAddressExist(msg.sender, participants.confirmed)){
            address[] storage confirmed = participants.confirmed;
            success = _removeAddressFromArray(msg.sender, confirmed);

            uint256 paymentAmount = 
                paymentSession.eventStartTime < block.timestamp ? 
                (block.timestamp.sub(paymentSession.eventStartTime)).mul(paymentSession.price).div(paymentSession.periodOfPenalty) : 0;
            if (paymentAmount > 0) {
                _unblockAndPay(paymentSession.tokenAddress, paymentAmount, author);
            }
            if (paymentAmount * 10 >= paymentSession.price) {
                Rating storage rating = paymentSession.rating;
                rating.cancelled += 1;
            }
            uint256 rejectedAmount = (paymentSession.price).sub(paymentAmount);
            _unblockAndReject(msg.sender, paymentSession.tokenAddress, rejectedAmount);
        }
        emit PurchaseCanceled(msg.sender, author, paymentSessionId);
    }

    function voteForPaymentSession(bool like, uint256 author, uint256 paymentSessionId) public {
        PaymentSession storage paymentSession = paymentSessionByAuthor[author][paymentSessionId];
        require(paymentSession.eventStartTime < block.timestamp, "Payment session not closed");
        Participants memory participants = paymentSession.participants;
        require(mainNFT.isAddressExist(msg.sender, participants.confirmed), "You arent in lists");
        require(!participantVoted[author][paymentSessionId][msg.sender], "Your already voted");
        participantVoted[author][paymentSessionId][msg.sender] = true;
        Rating storage rating = paymentSession.rating;
        if (like) {
            rating.like += 1;
        } else {
            rating.dislike += 1;
        }
        emit NewVote(like, msg.sender, author, paymentSessionId);
    }
    /***************User interfaces END***************/

    /***************Support BGN***************/
    function _removeAddressFromArray(address value, address[] storage array) internal returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == value) {
                array[i] = array[array.length - 1];
                array.pop();
                return true;
            }
        }
        return false;
    }

    function setInvitationToTg(uint256 author, uint256 paymentSessionId, address participant, string memory invitation) public onlyVerifierProvider{
        invitationToTg[author][paymentSessionId][participant] = invitation;
    }

    function owner() public view returns(address){
        return mainNFT.commissionCollector();
    }

    function ownerOf(uint256 author) public view returns (address){
        return mainNFT.ownerOf(author);
    }

    function setIMainNFT(address mainNFTAddress) public onlyOwner{
        mainNFT = IMainNFT(mainNFTAddress);
    }

    function setVerifierProvider(address _verifierProvider) public onlyOwner{
        verifierProvider = _verifierProvider;
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        (bool success, ) = owner().call{value: amount}("");
        require(success, "fail");
    }

    function withdrawTokens(address _address) external onlyOwner nonReentrant {
        IERC20 token = IERC20(_address);
        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 amount = tokenBalance;
        token.transfer(owner(), amount);
    }
    /***************Support END**************/

    receive() external payable {
        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "fail");
        emit Received(msg.sender, msg.value);
    }
}