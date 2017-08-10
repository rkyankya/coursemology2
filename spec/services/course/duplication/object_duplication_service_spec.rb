# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Course::Duplication::ObjectDuplicationService, type: :service do
  let(:instance) { create(:instance) }
  with_tenant(:instance) do
    let(:source_course) { create(:course) }
    let(:destination_course) { create(:course) }
    let(:options) { { current_course: source_course, target_course: destination_course } }
    let(:source_objects) { [] }
    let(:excluded_objects) { [] }

    describe '#duplicate_objects' do
      let(:duplicate_objects) do
        Course::Duplication::ObjectDuplicationService.duplicate_objects(source_objects, options)
      end

      context 'when an item fails to duplicate' do
        let(:milestone) { create(:course_lesson_plan_milestone, course: source_course) }
        let(:invalid_skill) do
          create(:course_assessment_skill, course: source_course).tap do |skill|
            skill.title = nil
          end
        end
        let(:source_objects) { [invalid_skill, milestone] }

        it 'rolls back the whole transaction' do
          expect { duplicate_objects }.to change { destination_course.lesson_plan_milestones.count }.by(0)
        end
      end

      context 'when an achievement is selected' do
        let(:achievement) { create(:course_achievement, :with_badge, course: source_course) }
        let(:source_objects) { [achievement] }

        it 'duplicates it' do
          expect { duplicate_objects }.to change { destination_course.achievements.count }.by(1)
          expect(duplicate_objects.first.title).to eq(achievement.title)
        end
      end

      context 'when an assessments are present' do
        let!(:assessments) { create_list(:assessment, 2, course: source_course) }
        let(:assessment) { assessments.first }
        let(:tab) { assessment.tab }
        let(:category) { tab.category }

        context 'when only a category is selected' do
          let(:source_objects) { category }

          it 'duplicates it without any tabs' do
            expect { duplicate_objects }.to change { destination_course.assessment_categories.count }.by(1)
            expect(duplicate_objects.title).to eq(category.title)
            expect(duplicate_objects.tabs.length).to eq(0)
          end
        end

        context 'when only a tab is selected' do
          let(:source_objects) { tab }
          before { category.update!(title: 'Non-default title') }

          it "adds it to the target course's default category without assessments" do
            expect { duplicate_objects }.to change {
              destination_course.reload.assessment_categories.map(&:tabs).flatten.count
            }.by(1)
            expect(duplicate_objects.title).to eq(tab.title)
            expect(duplicate_objects.category.title).not_to eq(category.reload.title)
            expect(duplicate_objects.assessments.length).to eq(0)
          end
        end

        context 'when an assessment is selected, but not its tab' do
          let(:source_objects) { [category, assessment] }
          before { tab.update!(title: 'Non-default title') }

          it "adds it to the target course's default tab" do
            expect { duplicate_objects }.to change { destination_course.assessments.count }.by(1)
            duplicate_category, duplicate_assessment = duplicate_objects
            expect(duplicate_assessment.title).to eq(assessment.title)
            expect(duplicate_assessment.tab.title).not_to eq(tab.reload.title)
            expect(duplicate_assessment.folder.parent.owner).not_to be(duplicate_category)
          end
        end

        context 'when a category is duplicated after its tab' do
          let(:source_objects) { [assessment, tab, category] }

          it 'associates the duplicates' do
            duplicate_assessment, duplicate_tab, duplicate_category = duplicate_objects
            expect(duplicate_category.tabs.length).to eq(1)
            expect(duplicate_tab.title).to eq(tab.title)
            expect(duplicate_assessment.folder.parent.owner).to be(duplicate_category)
          end
        end

        context 'when a tab is duplicated after its category' do
          let(:source_objects) { [assessment, category, tab] }

          it 'associates the duplicates' do
            duplicate_assessment, duplicate_category, duplicate_tab = duplicate_objects
            expect(duplicate_category.reload.tabs.length).to eq(1)
            expect(duplicate_tab.title).to eq(tab.title)
            expect(duplicate_assessment.folder.parent.owner).to be(duplicate_category)
          end
        end

        context 'when an assessment is duplicated after its tab' do
          let(:source_objects) { [tab, assessment] }

          it 'associates the duplicates' do
            duplicate_tab, duplicate_assessment = duplicate_objects
            expect(duplicate_assessment.tab).to be(duplicate_tab)
            expect(duplicate_assessment.folder.parent.owner).to be(duplicate_tab.category)
          end
        end

        context 'when a tab is duplicated after its assessment' do
          let(:source_objects) { [assessment, tab] }

          it 'associates the duplicates' do
            duplicate_assessment, duplicate_tab = duplicate_objects
            expect(duplicate_assessment.tab).to be(duplicate_tab)
            expect(duplicate_assessment.folder.parent.owner).to be(duplicate_tab.category)
          end
        end
      end

      context 'when assessment skills and branches are present' do
        let(:branch) do
          create(:course_assessment_skill_branch, :with_skill, course: source_course, skill_count: 2)
        end
        let(:skill) { branch.skills.first }

        context 'when an assessment skill is selected but not its branch' do
          let(:source_objects) { skill }

          it 'duplicates the skill but not the branch' do
            expect { duplicate_objects }.to change { destination_course.assessment_skills.count }.by(1)
            expect(duplicate_objects.title).to eq(skill.title)
            expect(duplicate_objects.skill_branch).to be_nil
          end
        end

        context 'when an assessment skill branch is selected but not the skills under it' do
          let(:source_objects) { branch }

          it 'duplicates the branch but not its skills' do
            expect { duplicate_objects }.to change { destination_course.assessment_skill_branches.count }.by(1)
            expect(duplicate_objects.title).to eq(branch.title)
            expect(duplicate_objects.skills.count).to eq(0)
          end
        end

        context 'when a skill is duplicated after its branch' do
          let(:source_objects) { [branch, skill] }

          it 'forms the association with the duplicate branch' do
            expect { duplicate_objects }.to change { destination_course.assessment_skills.count }.by(1)
            duplicate_branch, duplicate_skill = duplicate_objects
            expect(duplicate_skill.skill_branch).to be(duplicate_branch)
            expect(duplicate_branch.skills.count).to eq(1)
          end
        end

        context 'when a branch is duplicated after a skill under it' do
          let(:source_objects) { [skill, branch] }

          it 'forms associations with all its skills that are duplicated' do
            expect { duplicate_objects }.to change { destination_course.assessment_skills.count }.by(1)
            duplicate_skill, duplicate_branch = duplicate_objects
            expect(duplicate_skill.skill_branch).to be(duplicate_branch)
            expect(duplicate_branch.skills.count).to eq(1)
          end
        end

        context 'when a skill has an associated question' do
          let(:assessment) { create(:assessment, :with_mcq_question, course: source_course) }
          before do
            skill.questions << assessment.questions.first
            skill.save!
          end

          context 'when a skill is duplicated after its associated question' do
            let(:source_objects) { [assessment, skill] }

            it 'associates the duplicates' do
              expect { duplicate_objects }.to change { destination_course.assessment_skills.count }.by(1)
              duplicate_assessment, duplicate_skill = duplicate_objects
              expect(duplicate_assessment.reload.questions.first.skills.length).to eq(1)
              expect(duplicate_skill.questions.length).to eq(1)
              expect(duplicate_skill.questions.first.id).to eq(duplicate_assessment.questions.first.id)
            end
          end

          context 'when a question is duplicated after its associated skill' do
            let(:source_objects) { [skill, assessment] }

            it 'associates the duplicates' do
              expect { duplicate_objects }.to change { destination_course.assessment_skills.count }.by(1)
              duplicate_skill, duplicate_assessment = duplicate_objects
              expect(duplicate_assessment.questions.first.skills.length).to eq(1)
              expect(duplicate_skill.reload.questions.length).to eq(1)
              expect(duplicate_skill.questions.first.id).to eq(duplicate_assessment.questions.first.id)
            end
          end
        end
      end

      context 'when a forum is selected' do
        let(:forum) { create(:forum, course: source_course) }
        let(:source_objects) { [forum] }

        it 'duplicates it' do
          expect { duplicate_objects }.to change { destination_course.forums.count }.by(1)
          expect(duplicate_objects.first.name).to eq(forum.name)
        end
      end

      context 'when a lesson plan event is selected' do
        let(:event) { create(:course_lesson_plan_event, course: source_course) }
        let(:source_objects) { [event] }

        it 'duplicates it' do
          expect { duplicate_objects }.to change { destination_course.lesson_plan_events.count }.by(1)
          expect(duplicate_objects.first.title).to eq(event.title)
        end
      end

      context 'when a lesson plan milestone is selected' do
        let(:milestone) { create(:course_lesson_plan_milestone, course: source_course) }
        let(:source_objects) { [milestone] }

        it 'duplicates it' do
          expect { duplicate_objects }.to change { destination_course.lesson_plan_milestones.count }.by(1)
          expect(duplicate_objects.first.title).to eq(milestone.title)
        end
      end

      context 'when levels are selected' do
        let(:levels) { create_list(:course_level, 3, course: source_course) }
        let(:source_objects) { levels }

        it 'duplicates them' do
          expect { duplicate_objects }.to change { destination_course.levels.count }.by(3)
        end
      end

      context 'when a material folder is selected' do
        let(:folder) { create(:course_material_folder, course: source_course) }
        let!(:content) { create(:course_material, folder: folder) }
        let(:source_objects) { [folder] }

        it 'duplicates the folder and its contents' do
          expect { duplicate_objects }.to change { destination_course.material_folders.count }.by(1)
          expect(folder.reload.materials.first.name).to eq(content.name)
        end
      end

      context 'when a survey is selected' do
        let(:survey) { create(:survey, course: source_course) }
        let(:source_objects) { [survey] }

        it 'duplicates it' do
          expect { duplicate_objects }.to change { destination_course.surveys.count }.by(1)
          expect(duplicate_objects.first.title).to eq(survey.title)
        end
      end

      context 'when a video is selected' do
        let(:video) { create(:video, course: source_course) }
        let(:source_objects) { [video] }

        it 'duplicates it' do
          expect { duplicate_objects }.to change { destination_course.videos.count }.by(1)
          expect(duplicate_objects.first.title).to eq(video.title)
        end
      end
    end
  end
end
