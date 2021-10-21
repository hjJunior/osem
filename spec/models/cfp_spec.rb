# frozen_string_literal: true

require 'spec_helper'

describe Cfp do
  subject { create(:cfp) }
  let!(:conference) { create(:conference, end_date: Date.today) }
  let!(:cfp) { create(:cfp, cfp_type: 'events', start_date: Date.today - 2, end_date: Date.today - 1, program_id: conference.program.id) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:cfp_type) }
    it { is_expected.to validate_inclusion_of(:cfp_type).in_array(Cfp::TYPES) }
    it { is_expected.to validate_uniqueness_of(:cfp_type).ignoring_case_sensitivity.scoped_to(:program_id) }
  end

  describe '.for_events' do
    it 'returns the cfp for events when it exists' do
      expect(conference.program.cfps.for_events).to be_a Cfp
      expect(conference.program.cfps.for_events.cfp_type).to eq('events')
    end

    it 'returns nil when the cfp for events doesn\'t exist' do
      cfp.destroy!
      expect(conference.program.cfps.for_events).to eq nil
    end
  end

  describe '.for_tracks' do
    it 'returns the cfp for tracks when it exists' do
      call_for_tracks = create(:cfp, cfp_type: 'tracks', program: conference.program, end_date: Date.today)
      expect(conference.program.cfps.for_tracks).to eq call_for_tracks
    end

    it 'returns nil when the cfp for tracks doesn\'t exist' do
      expect(conference.program.cfps.for_tracks).to eq nil
    end
  end

  describe '#before_end_of_conference' do
    describe 'fails to save cfp' do
      it 'when cfp end_date is after conference end_date' do
        cfp.end_date = Date.today + 1
        expect(cfp.valid?).to be false
      end

      it 'when cfp start_date is after conference end_date' do
        cfp.start_date = Date.today + 1
        expect(cfp.valid?).to be false
      end
    end

    describe 'successfully saves cfp' do
      it 'when cfp end_date and start_date are before the conference end_date' do
        expect(cfp.valid?).to be true
      end
    end
  end

  describe '#start_after_end_date' do
    it 'succeeds when cfp start_date is after cfp end_date' do
      expect(cfp.valid?).to be true
    end

    it 'fails when cfp start_date is after cfp end_date' do
      cfp.start_date = Date.today
      expect(cfp.valid?).to be false
    end
  end

  describe '#notify_on_cfp_date_update?' do
    before :each do
      email_settings = conference.email_settings
      email_settings.send_on_cfp_dates_updated = true
      email_settings.cfp_dates_updated_subject = 'subject'
      email_settings.cfp_dates_updated_body = 'body text'
      email_settings.save!

      cfp.save!
    end

    describe 'returns true' do
      it 'when end_date changed' do
        cfp.end_date = Date.today
        expect(cfp.start_date_changed?).to eq false
        expect(cfp.end_date_changed?).to eq true
        expect(cfp.notify_on_cfp_date_update?).to eq true
      end

      it 'when start_date changed' do
        cfp.start_date = Date.today
        expect(cfp.end_date_changed?).to eq false
        expect(cfp.start_date_changed?).to eq true
        expect(cfp.notify_on_cfp_date_update?).to eq true
      end
    end

    describe 'returns false' do
      it 'when there is no change in cfp dates' do
        expect(cfp.start_date_changed?).to eq false
        expect(cfp.end_date_changed?).to eq false
        expect(cfp.notify_on_cfp_date_update?).to eq false
      end

      it 'when send_on_cfp_dates_updates is not set' do
        conference.email_settings.send_on_cfp_dates_updated = false
        conference.email_settings.save!
        cfp.end_date = Date.today

        expect(cfp.end_date_changed?).to eq true
        expect(cfp.notify_on_cfp_date_update?).to eq false
      end

      it 'when cfp_dates_updates_subject is not set' do
        conference.email_settings.cfp_dates_updated_subject = ''
        conference.email_settings.save!
        cfp.end_date = Date.today

        expect(cfp.end_date_changed?).to eq true
        expect(cfp.notify_on_cfp_date_update?).to eq false
      end

      it 'when cfp_dates_updates_template is not set' do
        conference.email_settings.cfp_dates_updated_body = ''
        conference.email_settings.save!
        cfp.end_date = Date.today

        expect(cfp.end_date_changed?).to eq true
        expect(cfp.notify_on_cfp_date_update?).to eq false
      end
    end
  end

  describe '#open?' do
    let(:timezone_minus11) { 'Pacific/Pago_Pago' }
    let(:timezone_plus14) { 'Pacific/Apia' }

    context 'when server timezone is the same as the conference' do
      before do
        Time.zone = timezone_minus11
        Timecop.freeze(Time.zone.now)

        cfp.program.conference.timezone = timezone_minus11

        @conference_day = Time.now.in_time_zone(cfp.program.conference.timezone).to_date
      end

      after do
        Timecop.return
      end

      context 'when the date is between the cfp range' do
        before do
          cfp.start_date = @conference_day
          cfp.end_date = @conference_day + 1.day
        end

        it 'returns true' do
          expect(cfp.open?).to be_truthy
        end
      end

      context 'when the date is not between the cfp range' do
        before do
          cfp.start_date = @conference_day + 1.day
          cfp.end_date = @conference_day + 2.days
        end

        it 'returns false' do
          expect(cfp.open?).to be_falsy
        end
      end
    end

    context 'when server timezone is on behind as the conference' do
      before do
        Time.zone = timezone_minus11
        Timecop.freeze(Time.zone.now)

        cfp.program.conference.timezone = timezone_plus14

        @conference_day = Time.now.in_time_zone(cfp.program.conference.timezone).to_date
      end

      after do
        Timecop.return
      end

      context 'when the date is between the cfp range' do
        before do
          cfp.start_date = @conference_day
          cfp.end_date = @conference_day + 1.day
        end

        it 'returns true' do
          expect(cfp.open?).to be_truthy
        end
      end

      context 'when the date is not between the cfp range' do
        before do
          cfp.start_date = @conference_day + 1.day
          cfp.end_date = @conference_day + 2.days
        end

        it 'returns false' do
          expect(cfp.open?).to be_falsy
        end
      end
    end

    context 'when server timezone is on ahead as the conference' do
      before do
        Time.zone = timezone_plus14
        Timecop.freeze(Time.zone.now)

        cfp.program.conference.timezone = timezone_minus11

        @conference_day = Time.now.in_time_zone(cfp.program.conference.timezone).to_date
      end

      after do
        Timecop.return
      end

      context 'when the date is between the cfp range' do
        before do
          cfp.start_date = @conference_day - 1.day
          cfp.end_date = @conference_day
        end

        it 'returns true' do
          expect(cfp.open?).to be_truthy
        end
      end

      context 'when the date is not between the cfp range' do
        before do
          cfp.start_date = @conference_day - 2.days
          cfp.end_date = @conference_day - 1.day
        end

        it 'returns false' do
          expect(cfp.open?).to be_falsy
        end
      end
    end
  end
end
