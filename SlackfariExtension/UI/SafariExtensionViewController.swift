//
//  Presenter.swift
//  Slackfari
//
//  Created by Alberto Moral on 16/08/2017.
//  Copyright © 2017 Alberto Moral. All rights reserved.
//

import SafariServices
import SlackWebAPIKit
import RxSwift
import Cartography

class SafariExtensionViewController: SFSafariExtensionViewController {
    
    static let shared = SafariExtensionViewController()

    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var addTeamButton: NSButton!
    @IBOutlet weak var buttonSend: NSButton!
    @IBOutlet weak var teamNameLabel: NSTextField!
    
    fileprivate var presenter: Presenter?
    fileprivate let disposeBag = DisposeBag()
    
    let constraintGroup = ConstraintGroup()
    
    var url: String?
    var channelDataProvider: ChannelTableViewDataProvider?
    var teamDataProvider: TeamCollectionViewDataProvider?
    
    lazy var addTeamView: AddTeamView = {
        let addTeam = AddTeamView()
        addTeam.delegate = self
        return addTeam
    }()
    
    override func viewWillAppear() {
        super.viewWillAppear()
        configureTableView()
        configureCollectionView()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        guard let team = UserDefaults.standard.getTeam(), let token = team["token"] else { return }
        API.sharedInstance.set(token: token)
        presenter = Presenter()
        getAllChannels()
    }
    
    private func configureTableView() {
        channelDataProvider = ChannelTableViewDataProvider(tableView: tableView)
        tableView.rowSizeStyle = .large
        tableView.backgroundColor = NSColor.clear
    }
    
    private func configureCollectionView() {
        teamDataProvider = TeamCollectionViewDataProvider(collectionView: collectionView)
        teamDataProvider?.delegate = self
        guard let teams = UserDefaults.standard.array(forKey: "teams") as? UserDefaultTeams else {
            return
        }
        teamDataProvider?.set(items: teams)
    }
    
    // MARK: Send Message
    
    @IBAction func sendMessage(_ sender: Any) {
        guard let post = url else { return }
        guard let selected = channelDataProvider?.getItem(at: tableView.selectedRow) else { return }
        let type = checkChannel(type: selected)
        send(message: post, toChannel: selected.name, withType: type)
    }
    
    private func checkChannel(type: Channelable) -> MessageType {
        if type is ChannelViewModel {
            return .channel
        } else if type is GroupViewModel {
            return .group
        } else {
            return .user
        }
    }
    
    private func send(message: String, toChannel channel: String, withType type: MessageType) {
        presenter?.send(message: message, channel: channel, type: type).subscribe(onNext: { isSent in
            print("message sent")
        }, onError: { (error) in
            print("Error \(error)")
        }).disposed(by: disposeBag)
    }
    
    // MARK: Get team's information
    
    fileprivate func getAllChannels() {
        guard let presenter = presenter else { return }
        presenter.getUsers()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] users in
                guard let strongSelf = self else { return }
                strongSelf.buildUsersViewModel(users: users)
                strongSelf.tableView.reloadData()
            }, onError: { error in
                print("Error \(error)")
            }).disposed(by: disposeBag)
        
        presenter.getChannels()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] channels in
                guard let strongSelf = self else { return }
                strongSelf.buildChannelsViewModel(channels: channels)
                strongSelf.tableView.reloadData()
                }, onError: { error in
                    print("Error \(error)")
            }).disposed(by: disposeBag)
        
        presenter.getGroups()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] groups in
                guard let strongSelf = self else { return }
                strongSelf.buildGroupsViewModel(groups: groups)
                strongSelf.tableView.reloadData()
                }, onError: { error in
                    print("Error \( error)")
            }).disposed(by: disposeBag)
        
        presenter.getTeamInfo()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] team in
                guard let strongSelf = self else { return }
                strongSelf.teamNameLabel.stringValue = team.name ?? ""
                }, onError: { [weak self] error in
                    guard let strongSelf = self else { return }
                    strongSelf.teamNameLabel.stringValue = "Error"
                }, onCompleted: {
                    print("Completed")
            }).disposed(by: disposeBag)
    }
}

// MARK: - AddteamViewDelegate

extension SafariExtensionViewController: AddTeamViewDelegate {
    func didTapOnCloseButton() {
        addTeamView.removeFromSuperview()
    }
    
    func didTapOnAddTeamButton(teamName: String, token: String) {
        let saveTemporalToken = API.sharedInstance.getToken()
        API.sharedInstance.set(token: token)
        presenter = Presenter()
        
        presenter?.getTeamInfo()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] team in
                guard let strongSelf = self else { return }
                strongSelf.teamNameLabel.stringValue = teamName
                strongSelf.saveTeam(teamIcon: team.icon!, teamName: teamName, token: token)
                }, onError: { [weak self] error in
                    guard let strongSelf = self else { return }
                    print("Error \(error)")
                    API.sharedInstance.set(token: saveTemporalToken ?? "")
                    strongSelf.presenter = Presenter()
            }, onCompleted: {
                print("Completed")
            }).disposed(by: disposeBag)
    }
    
    private func saveTeam(teamIcon: String, teamName: String, token: String) {
        save(teamIcon: teamIcon, teamName: teamName, token: token) {
            teamDataProvider?.set(items: $0)
            collectionView.reloadData()
        }
    }
}

// MARK: - Build View Models

extension SafariExtensionViewController {
    fileprivate func buildUsersViewModel(users: [User]) {
        guard let dataProvider = channelDataProvider else { return }
        let usersViewModel: [Channelable] = users.flatMap(UserViewModel.init)
        dataProvider.add(items: usersViewModel)
    }
    
    fileprivate func buildChannelsViewModel(channels: [Channel]) {
        guard let dataProvider = channelDataProvider else { return }
        let channelsViewModel: [Channelable] = channels.flatMap(ChannelViewModel.init)
        dataProvider.add(items: channelsViewModel)
    }
    
    fileprivate func buildGroupsViewModel(groups: [Group]) {
        guard let dataProvider = channelDataProvider else { return }
        let groupsViewModel: [Channelable] = groups.flatMap(GroupViewModel.init)
        dataProvider.add(items: groupsViewModel)
    }
}

// MARK: - CollectionViewDataProviderDelegate

extension SafariExtensionViewController: TeamCollectionViewDataProviderDelegate {
    func didTapOnTeam(withToken token: String) {
        //  Clean channels
        guard let dataProvider = channelDataProvider else { return }
        dataProvider.removeItems()
        
        API.sharedInstance.set(token: token)
        presenter = Presenter()
        getAllChannels()
    }
}
